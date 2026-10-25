"""Cookieless statistics for the public site (booqy.se): ingest and rollup.

TRIGGER
  - CloudFront (landing distribution, GET /api/collect, OAC-signed) calls this
    function's URL with one hit from site/assets/stats.js in the booqy-website
    repo. The URL itself refuses anything that doesn't come through that
    distribution.
  - EventBridge Scheduler every 15 minutes: {"task": "rollup"} (optionally
    "days": ["yyyy-mm-dd", ...] to rebuild days still in the raw store).

PURPOSE
  Count visits without storing or reading anything on the visitor's device
  (no cookies, no local storage, no fingerprinting), so no consent is needed
  (LEK 9 kap. 28 §). A visitor is a hash of a random salt that changes every
  day (Europe/Stockholm), the site, the IP address and the user agent. The IP
  and the user agent are never stored; only the hash, the browser and OS
  family and CloudFront's country/region/city are. Yesterday's salt is
  deleted, so yesterday's hashes can't be linked to today's. A browser that
  sends Global Privacy Control or Do Not Track is not counted at all (the
  beacon sends nothing; this function also drops such hits).

  Hit (query string, all short keys, anything else is a 400):
    t   pv (page view) | en (engagement, sent when the page is hidden) | ev (event)
    p   path ("/catering")
    r   referrer host, page views only, other sites only
    us um uc ux ut   utm_source, utm_medium, utm_campaign, utm_content, utm_term
    w   screen width bucket: m (< 600 px) | t (< 1100 px) | d
    l   language ("sv-SE")
    s   engaged seconds since the last engagement hit (en)
    d   deepest scroll band reached, 0 | 25 | 50 | 75 | 100 (en)
    e   event: demo (Boka en demo sent) | cta (call to action clicked) | tab (showcase tab)
    n   event label ("/demo", "catering")

  Dropped silently (204): bots (user agent list, no Sec-Fetch-Site:
  same-origin), GPC/DNT, more than RATE_MAX hits from one visitor in
  RATE_WINDOW seconds (per container; reserved concurrency caps the rest).

  Raw hits are kept RAW_DAYS days. The rollup turns a day's hits into visits
  (a new visit after 30 minutes without a hit) and writes one aggregate per
  day, kept AGG_DAYS days (25 months), read by Booqy Console's Website page.

ENV_VARS
  TABLE_NAME        site-analytics table (raw hits, daily aggregates)
  STATE_TABLE_NAME  site-analytics-state table (daily salts; no backups)
  SITE              the platform domain the hits are for (dev.booqy.se)

AWS RESOURCE ACCESS
  dynamodb PutItem/Query on TABLE_NAME; GetItem/PutItem/DeleteItem on STATE_TABLE_NAME.
"""

import hashlib
import json
import logging
import os
import re
import secrets
import time
from datetime import date, datetime, timedelta, timezone
from urllib.parse import unquote

log = logging.getLogger()
log.setLevel(logging.INFO)

TABLE = os.environ.get("TABLE_NAME", "")
STATE_TABLE = os.environ.get("STATE_TABLE_NAME", "")
SITE = os.environ.get("SITE", "")

RAW_DAYS = 30
AGG_DAYS = 762  # 25 months
VISIT_GAP_MS = 30 * 60 * 1000
ENGAGED_SECONDS = 10  # a visit is engaged (not a bounce) from 10 s, 2 page views or a conversion
RATE_MAX, RATE_WINDOW = 120, 600
TOP_N = 200

BOT_RE = re.compile(
    r"bot|crawl|spider|slurp|scrap|headless|phantom|puppeteer|playwright|selenium|lighthouse|pagespeed|gtmetrix"
    r"|pingdom|uptime|monitor|python|curl|wget|httpclient|okhttp|go-http|java/|axios|node-fetch|libwww|"
    r"facebookexternalhit|embedly|preview|semrush|ahrefs|mj12|yandex|baidu|petal|bytespider|gptbot|claude|"
    r"anthropic|perplexity|ccbot|chatgpt",
    re.I,
)
PATH_RE = re.compile(r"^/[A-Za-z0-9/_.~%-]{0,199}$")
HOST_RE = re.compile(r"^[a-z0-9]([a-z0-9-]*[a-z0-9])?(\.[a-z0-9]([a-z0-9-]*[a-z0-9])?)+$")
LANG_RE = re.compile(r"^([a-zA-Z]{2,3})(-[a-zA-Z0-9]{2,8})*$")
LABEL_RE = re.compile(r"^[a-z0-9/_.#%-]{1,60}$")
UTM_KEYS = ("us", "um", "uc", "ux", "ut")
KEYS = {"t", "p", "r", "w", "l", "s", "d", "e", "n", *UTM_KEYS}
TYPES = {"pv", "en", "ev"}
EVENTS = {"demo", "cta", "tab"}
WIDTHS = {"m": "mobile", "t": "tablet", "d": "desktop"}
BANDS = {"0", "25", "50", "75", "100"}

SEARCH_RE = re.compile(
    r"^(www\.)?(google|bing|duckduckgo|yahoo|ecosia|yandex|baidu|startpage|qwant|brave|kagi)\.[a-z.]+$"
    r"|^search\.(yahoo|brave)\.[a-z.]+$"
)
SOCIAL = ("facebook.com", "fb.com", "fb.me", "instagram.com", "linkedin.com", "lnkd.in", "t.co", "twitter.com",
          "x.com", "tiktok.com", "youtube.com", "youtu.be", "pinterest.com", "reddit.com", "threads.net",
          "snapchat.com", "messenger.com", "whatsapp.com", "bsky.app")

_ddb_client = None
_salts: dict[str, str] = {}
_recent: dict[str, list[int]] = {}


def _ddb():
    global _ddb_client
    if _ddb_client is None:
        import boto3

        _ddb_client = boto3.client("dynamodb")
    return _ddb_client


# --- time: Europe/Stockholm without a tz database (EU rule: CEST from the last
# Sunday of March to the last Sunday of October, 01:00 UTC both ways) ---------

def _last_sunday(year: int, month: int) -> date:
    d = (date(year, month + 1, 1) if month < 12 else date(year + 1, 1, 1)) - timedelta(days=1)
    return d - timedelta(days=(d.weekday() + 1) % 7)


def stockholm(now: datetime) -> datetime:
    utc = now.astimezone(timezone.utc)
    start = datetime.combine(_last_sunday(utc.year, 3), datetime.min.time(), timezone.utc) + timedelta(hours=1)
    end = datetime.combine(_last_sunday(utc.year, 10), datetime.min.time(), timezone.utc) + timedelta(hours=1)
    return utc + timedelta(hours=2 if start <= utc < end else 1)


def stockholm_day(now: datetime) -> str:
    return stockholm(now).date().isoformat()


# --- ingest -------------------------------------------------------------------

def is_bot(headers: dict) -> bool:
    ua = headers.get("user-agent", "")
    if not ua or len(ua) > 512 or BOT_RE.search(ua):
        return True
    # Every current browser sends Fetch Metadata; the beacon is same-origin.
    return headers.get("sec-fetch-site") != "same-origin"


def opted_out(headers: dict) -> bool:
    return headers.get("sec-gpc") == "1" or headers.get("dnt") == "1"


def _text(value: str, limit: int) -> str:
    value = value.strip()
    if not value or len(value) > limit or any(ord(c) < 32 or ord(c) == 127 for c in value):
        raise ValueError("invalid")
    return value


def normalize_path(path: str) -> str:
    path = path.split("?", 1)[0].split("#", 1)[0]
    if not PATH_RE.match(path):
        raise ValueError("p")
    if path.endswith("/index.html"):
        path = path[: -len("index.html")]
    elif path.endswith(".html"):
        path = path[:-5]
    if len(path) > 1:
        path = path.rstrip("/") or "/"
    return path.lower()


def validate(params: dict) -> dict:
    """The hit, cleaned: raises ValueError (400) on anything unexpected."""
    unknown = set(params) - KEYS
    if unknown:
        raise ValueError(f"unknown: {sorted(unknown)[0]}")
    t = params.get("t")
    if t not in TYPES:
        raise ValueError("t")
    hit = {"t": t, "p": normalize_path(params.get("p") or "")}
    if params.get("w"):
        if params["w"] not in WIDTHS:
            raise ValueError("w")
        hit["w"] = params["w"]
    if params.get("l"):
        m = LANG_RE.match(params["l"])
        if not m or len(params["l"]) > 35:
            raise ValueError("l")
        hit["l"] = m.group(1).lower()
    if t == "pv":
        ref = (params.get("r") or "").strip().lower()
        if ref:
            if len(ref) > 253 or not HOST_RE.match(ref):
                raise ValueError("r")
            ref = ref[4:] if ref.startswith("www.") else ref
            if ref != SITE and not ref.endswith("." + SITE):
                hit["r"] = ref
        for k in UTM_KEYS:
            if params.get(k):
                hit[k] = _text(params[k], 100).lower()
    elif t == "en":
        try:
            s = int(params.get("s", "0"))
        except ValueError:
            raise ValueError("s") from None
        if not 0 <= s <= 1800:
            raise ValueError("s")
        d = params.get("d", "0")
        if d not in BANDS:
            raise ValueError("d")
        hit["s"], hit["d"] = s, int(d)
    else:
        if params.get("e") not in EVENTS:
            raise ValueError("e")
        hit["e"] = params["e"]
        if params.get("n"):
            label = params["n"].strip().lower()
            if not LABEL_RE.match(label):
                raise ValueError("n")
            hit["n"] = label
    return hit


def browser_family(ua: str) -> str:
    for needle, name in (("Edg", "Edge"), ("OPR/", "Opera"), ("Opera", "Opera"), ("SamsungBrowser", "Samsung Internet"),
                         ("Firefox/", "Firefox"), ("FxiOS", "Firefox"), ("CriOS", "Chrome"), ("Chrome/", "Chrome")):
        if needle in ua:
            return name
    return "Safari" if "Safari/" in ua and "Version/" in ua else "Other"


def os_family(ua: str) -> str:
    for needle, name in (("iPhone", "iOS"), ("iPod", "iOS"), ("iPad", "iPadOS"), ("Android", "Android"),
                         ("Windows", "Windows"), ("CrOS", "ChromeOS"), ("Macintosh", "macOS"), ("Mac OS X", "macOS"),
                         ("Linux", "Linux")):
        if needle in ua:
            return name
    return "Other"


def device_of(width: str | None, ua: str) -> str:
    if width:
        return WIDTHS[width]
    if "iPad" in ua or "Tablet" in ua:
        return "tablet"
    return "mobile" if "Mobi" in ua else "desktop"


def _viewer_ip(headers: dict) -> str:
    addr = headers.get("cloudfront-viewer-address", "")
    if addr:
        return addr.rsplit(":", 1)[0].strip("[]")  # "198.51.100.10:46532", "2001:db8::1:46532"
    return headers.get("x-forwarded-for", "").split(",")[0].strip()


def _header_text(headers: dict, name: str, limit: int = 80) -> str | None:
    raw = unquote(headers.get(name, "")).strip()
    return raw if raw and len(raw) <= limit and all(ord(c) >= 32 for c in raw) else None


def geo(headers: dict) -> dict:
    out = {}
    cc = headers.get("cloudfront-viewer-country", "").upper()
    if re.fullmatch(r"[A-Z]{2}", cc):
        out["cc"] = cc
        region = _header_text(headers, "cloudfront-viewer-country-region-name") or _header_text(
            headers, "cloudfront-viewer-country-region", 8)
        city = _header_text(headers, "cloudfront-viewer-city")
        if region:
            out["rg"] = region
        if city:
            out["ci"] = city
    return out


def get_salt(day: str) -> str:
    """The salt for one Stockholm day: random, created by the first hit of the
    day, shared by every container through the state table (no backups, TTL,
    deleted by the rollup once the day is over)."""
    if day in _salts:
        return _salts[day]
    key = {"PK": {"S": f"SALT#{day}"}}
    item = _ddb().get_item(TableName=STATE_TABLE, Key=key, ConsistentRead=True).get("Item")
    if not item:
        value = secrets.token_hex(32)
        try:
            _ddb().put_item(TableName=STATE_TABLE, Item={**key, "salt": {"S": value}, "expiresAt": {
                "N": str(int(time.time()) + 2 * 86400)}}, ConditionExpression="attribute_not_exists(PK)")
            item = {"salt": {"S": value}}
        except Exception as e:  # another container won the race: use its salt
            if getattr(e, "response", {}).get("Error", {}).get("Code") != "ConditionalCheckFailedException":
                raise
            item = _ddb().get_item(TableName=STATE_TABLE, Key=key, ConsistentRead=True)["Item"]
    for old in [d for d in _salts if d != day]:
        del _salts[old]
    _salts[day] = item["salt"]["S"]
    return _salts[day]


def visitor_hash(salt: str, site: str, ip: str, ua: str) -> str:
    return hashlib.sha256(f"{salt}|{site}|{ip}|{ua}".encode()).hexdigest()[:16]


def rate_limited(visitor: str, now_s: int) -> bool:
    hits = [t for t in _recent.get(visitor, []) if t > now_s - RATE_WINDOW]
    hits.append(now_s)
    _recent[visitor] = hits
    if len(_recent) > 5000:  # keep the container's memory bounded
        for k in [k for k, v in _recent.items() if v[-1] <= now_s - RATE_WINDOW]:
            del _recent[k]
    return len(hits) > RATE_MAX


def _reply(status: int, body: dict | None = None) -> dict:
    return {"statusCode": status, "headers": {"Cache-Control": "no-store", "Content-Type": "application/json"},
            "body": json.dumps(body) if body else ""}


def ingest(event: dict, now: datetime) -> dict:
    method = event.get("requestContext", {}).get("http", {}).get("method", "")
    if method != "GET":
        return _reply(405, {"error": "method_not_allowed"})
    headers = {k.lower(): v for k, v in (event.get("headers") or {}).items()}
    if opted_out(headers) or is_bot(headers):
        return _reply(204)
    try:
        hit = validate(event.get("queryStringParameters") or {})
    except ValueError as e:
        return _reply(400, {"error": "validation_failed", "field": str(e)})

    ua = headers["user-agent"]
    day = stockholm_day(now)
    visitor = visitor_hash(get_salt(day), SITE, _viewer_ip(headers), ua)
    now_s = int(now.timestamp())
    if rate_limited(visitor, now_s):
        return _reply(204)

    hit.update(geo(headers))
    hit["dv"] = device_of(hit.pop("w", None), ua)
    hit["br"], hit["os"] = browser_family(ua), os_family(ua)
    item = {"PK": {"S": f"RAW#{day}"}, "SK": {"S": f"{int(now.timestamp() * 1000):013d}#{secrets.token_hex(3)}"},
            "v": {"S": visitor}, "expiresAt": {"N": str(now_s + RAW_DAYS * 86400)}}
    for k, v in hit.items():
        item[k] = {"N": str(v)} if isinstance(v, int) else {"S": v}
    _ddb().put_item(TableName=TABLE, Item=item)
    return _reply(204)


# --- rollup -------------------------------------------------------------------

def classify(ref: str | None, utm: dict) -> str:
    """direct, search, social, referral or campaign (any utm_source, utm_medium or utm_campaign)."""
    if utm.get("us") or utm.get("um") or utm.get("uc"):
        return "campaign"
    if not ref:
        return "direct"
    if SEARCH_RE.match(ref):
        return "search"
    if any(ref == s or ref.endswith("." + s) for s in SOCIAL):
        return "social"
    return "referral"


def _bump(table: dict, key: str, visit: dict) -> None:
    row = table.setdefault(key, {"v": 0, "c": 0, "b": 0})
    row["v"] += 1
    row["c"] += 1 if visit["conversions"] else 0
    row["b"] += 1 if visit["bounce"] else 0


def _weight(row) -> int:
    return row if isinstance(row, int) else row.get("v", row.get("pv", 0))


def _top(table: dict, n: int = TOP_N) -> dict:
    """The n biggest rows, so a day's aggregate stays far below DynamoDB's 400 KB item limit."""
    if len(table) <= n:
        return table
    return dict(sorted(table.items(), key=lambda kv: -_weight(kv[1]))[:n])


def build_stats(hits: list[dict]) -> dict:
    """One day's hits (each with "ts" in ms and "v", the visitor hash) as the day's aggregate."""
    by_visitor: dict[str, list[dict]] = {}
    for h in sorted(hits, key=lambda h: (h["ts"], h["t"] != "pv")):  # a page view first within the same ms
        by_visitor.setdefault(h["v"], []).append(h)

    visits = []
    for vhits in by_visitor.values():
        current, last = None, 0
        for h in vhits:
            if h["t"] == "pv" and (current is None or h["ts"] - last > VISIT_GAP_MS):
                current = {"first": h, "pvs": [], "events": [], "engaged": 0, "depth": {}, "conversions": 0}
                visits.append(current)
            if current is None:
                continue  # engagement or an event without a page view that day (just after midnight)
            last = h["ts"]
            if h["t"] == "pv":
                current["pvs"].append(h)
            elif h["t"] == "en":
                current["engaged"] += int(h.get("s", 0))
                current["depth"][h["p"]] = max(current["depth"].get(h["p"], 0), int(h.get("d", 0)))
                current.setdefault("seconds", {}).setdefault(h["p"], 0)
                current["seconds"][h["p"]] += int(h.get("s", 0))
            else:
                current["events"].append(h)
                if h.get("e") == "demo":
                    current["conversions"] += 1

    s = {"visitors": 0, "visits": len(visits), "pageviews": 0, "conversions": 0, "convertedVisits": 0, "bounces": 0,
         "engagedSeconds": 0, "scroll": {b: 0 for b in sorted(BANDS, key=int)}, "hours": [0] * 24,
         "sources": {}, "referrers": {}, "campaigns": {}, "contents": {}, "terms": {}, "landing": {}, "pages": {},
         "countries": {}, "regions": {}, "cities": {}, "devices": {}, "browsers": {}, "os": {}, "languages": {},
         "events": {"cta": {}, "tab": {}}}
    s["visitors"] = len({v["first"]["v"] for v in visits})
    for v in visits:
        f = v["first"]
        v["bounce"] = len(v["pvs"]) < 2 and v["engaged"] < ENGAGED_SECONDS and not v["conversions"]
        s["pageviews"] += len(v["pvs"])
        s["conversions"] += v["conversions"]
        s["convertedVisits"] += 1 if v["conversions"] else 0
        s["bounces"] += 1 if v["bounce"] else 0
        s["engagedSeconds"] += v["engaged"]
        s["hours"][stockholm(datetime.fromtimestamp(f["ts"] / 1000, timezone.utc)).hour] += 1

        utm = {k: f.get(k) for k in UTM_KEYS}
        _bump(s["sources"], classify(f.get("r"), utm), v)
        if f.get("r"):
            _bump(s["referrers"], f["r"], v)
        if any(utm.get(k) for k in ("us", "um", "uc")):
            _bump(s["campaigns"], "|".join(utm.get(k) or "" for k in ("us", "um", "uc")), v)
            if utm.get("ux"):
                _bump(s["contents"], utm["ux"], v)
            if utm.get("ut"):
                _bump(s["terms"], utm["ut"], v)
        _bump(s["landing"], f["p"], v)
        if f.get("cc"):
            _bump(s["countries"], f["cc"], v)
            if f.get("rg"):
                _bump(s["regions"], f"{f['cc']}|{f['rg']}", v)
            if f.get("ci"):
                _bump(s["cities"], f"{f['cc']}|{f['ci']}", v)
        for dim, field in (("devices", "dv"), ("browsers", "br"), ("os", "os"), ("languages", "l")):
            if f.get(field):
                _bump(s[dim], f[field], v)

        for pv in v["pvs"]:
            page = s["pages"].setdefault(pv["p"], {"pv": 0, "s": 0, "n": 0})
            page["pv"] += 1
        for path, secs in v.get("seconds", {}).items():
            page = s["pages"].setdefault(path, {"pv": 0, "s": 0, "n": 0})
            page["s"] += secs
            page["n"] += 1
        for depth in v["depth"].values():
            s["scroll"][str(depth)] += 1
        for ev in v["events"]:
            if ev.get("e") in ("cta", "tab"):
                bucket = s["events"][ev["e"]]
                label = ev.get("n") or "-"
                bucket[label] = bucket.get(label, 0) + 1

    for k in ("sources", "referrers", "campaigns", "contents", "terms", "landing", "pages", "countries", "regions",
              "cities", "devices", "browsers", "os", "languages"):
        s[k] = _top(s[k])
    s["events"] = {k: _top(v) for k, v in s["events"].items()}
    return s


def _from_ddb(item: dict) -> dict:
    out = {}
    for k, v in item.items():
        out[k] = int(v["N"]) if "N" in v else v.get("S")
    return out


def raw_hits(day: str) -> list[dict]:
    hits, start = [], None
    while True:
        kwargs = {"TableName": TABLE, "KeyConditionExpression": "PK = :pk", "ExpressionAttributeValues": {
            ":pk": {"S": f"RAW#{day}"}}}
        if start:
            kwargs["ExclusiveStartKey"] = start
        page = _ddb().query(**kwargs)
        for item in page.get("Items", []):
            h = _from_ddb(item)
            h["ts"] = int(h["SK"].split("#", 1)[0])
            hits.append(h)
        start = page.get("LastEvaluatedKey")
        if not start:
            return hits


def rollup(event: dict, now: datetime) -> dict:
    today = date.fromisoformat(stockholm_day(now))
    days = event.get("days") or [(today - timedelta(days=1)).isoformat(), today.isoformat()]
    if not isinstance(days, list) or len(days) > RAW_DAYS + 1:
        raise ValueError("days")
    done = {}
    for day in days:
        d = date.fromisoformat(day)
        stats = build_stats(raw_hits(d.isoformat()))
        expires = int(datetime.combine(d, datetime.min.time(), timezone.utc).timestamp()) + AGG_DAYS * 86400
        _ddb().put_item(TableName=TABLE, Item={
            "PK": {"S": "AGG"}, "SK": {"S": f"DAY#{d.isoformat()}"}, "stats": {"S": json.dumps(stats, separators=(",", ":"))},
            "updatedAt": {"S": now.astimezone(timezone.utc).isoformat()}, "expiresAt": {"N": str(expires)}})
        done[d.isoformat()] = {"visits": stats["visits"], "pageviews": stats["pageviews"]}
    # The day is over: its salt goes, so its hashes can't be matched with anything any more.
    for n in (1, 2, 3):
        _ddb().delete_item(TableName=STATE_TABLE, Key={"PK": {"S": f"SALT#{(today - timedelta(days=n)).isoformat()}"}})
    _ddb().put_item(TableName=TABLE, Item={"PK": {"S": "JOB"}, "SK": {"S": "latest"},
                                           "asOf": {"S": now.astimezone(timezone.utc).isoformat()},
                                           "days": {"S": json.dumps(done)}})
    return {"status": "ok", "days": done}


def handler(event, context=None):
    now = datetime.now(timezone.utc)
    if event.get("task") == "rollup":
        result = rollup(event, now)
        log.info(json.dumps(result))
        return result
    return ingest(event, now)
