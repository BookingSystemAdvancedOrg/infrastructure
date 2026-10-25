"""Run: python3 -m unittest discover -s site-analytics/tests"""

import json
import os
import sys
import unittest
from datetime import datetime, timezone
from unittest import mock

os.environ.setdefault("TABLE_NAME", "dev-site-analytics")
os.environ.setdefault("STATE_TABLE_NAME", "dev-site-analytics-state")
os.environ.setdefault("SITE", "dev.booqy.se")

sys.path.insert(0, os.path.join(os.path.dirname(__file__), "..", "src"))

import handler  # noqa: E402

CHROME = ("Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) "
          "Chrome/130.0.0.0 Safari/537.36")
IPHONE = ("Mozilla/5.0 (iPhone; CPU iPhone OS 18_0 like Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko) "
          "Version/18.0 Mobile/15E148 Safari/604.1")
NOW = datetime(2026, 10, 20, 9, 30, tzinfo=timezone.utc)


class ConditionalCheckFailed(Exception):
    response = {"Error": {"Code": "ConditionalCheckFailedException"}}


class FakeDynamo:
    """Just the calls the handler makes, keyed by (table, PK, SK)."""

    def __init__(self):
        self.items = {}
        self.deleted = []

    def _key(self, table, key):
        return table, key["PK"]["S"], key.get("SK", {}).get("S")

    def put_item(self, TableName, Item, ConditionExpression=None):
        k = self._key(TableName, Item)
        if ConditionExpression and k in self.items:
            raise ConditionalCheckFailed()
        self.items[k] = Item

    def get_item(self, TableName, Key, ConsistentRead=False):
        item = self.items.get(self._key(TableName, Key))
        return {"Item": item} if item else {}

    def delete_item(self, TableName, Key):
        self.deleted.append(Key["PK"]["S"])
        self.items.pop(self._key(TableName, Key), None)

    def query(self, TableName, KeyConditionExpression, ExpressionAttributeValues, **_):
        pk = ExpressionAttributeValues[":pk"]["S"]
        rows = [v for (t, p, _s), v in sorted(self.items.items()) if t == TableName and p == pk]
        return {"Items": rows}


def headers(ua=CHROME, **extra):
    h = {"user-agent": ua, "sec-fetch-site": "same-origin", "cloudfront-viewer-address": "203.0.113.7:51234",
         "cloudfront-viewer-country": "SE", "cloudfront-viewer-country-region-name": "Stockholms l%C3%A4n",
         "cloudfront-viewer-city": "Stockholm"}
    h.update(extra)
    return h


def event(params, hdrs=None, method="GET"):
    return {"requestContext": {"http": {"method": method}}, "headers": hdrs if hdrs is not None else headers(),
            "queryStringParameters": params}


class Base(unittest.TestCase):
    def setUp(self):
        self.ddb = FakeDynamo()
        p = mock.patch.object(handler, "_ddb", return_value=self.ddb)
        p.start()
        self.addCleanup(p.stop)
        handler._salts.clear()
        handler._recent.clear()

    def raw(self):
        return [v for (t, pk, _), v in self.ddb.items.items() if pk.startswith("RAW#")]


class HashAndSaltTest(Base):
    def test_hash_depends_on_salt_site_ip_and_user_agent(self):
        h = handler.visitor_hash("s1", "booqy.se", "203.0.113.7", CHROME)
        self.assertEqual(h, handler.visitor_hash("s1", "booqy.se", "203.0.113.7", CHROME))
        self.assertEqual(len(h), 16)
        for other in (("s2", "booqy.se", "203.0.113.7", CHROME), ("s1", "dev.booqy.se", "203.0.113.7", CHROME),
                      ("s1", "booqy.se", "203.0.113.8", CHROME), ("s1", "booqy.se", "203.0.113.7", IPHONE)):
            self.assertNotEqual(h, handler.visitor_hash(*other))

    def test_salt_is_random_per_day_and_shared(self):
        a = handler.get_salt("2026-10-20")
        self.assertEqual(len(a), 64)
        self.assertEqual(a, handler.get_salt("2026-10-20"))
        handler._salts.clear()  # another container reads the same salt
        self.assertEqual(a, handler.get_salt("2026-10-20"))
        b = handler.get_salt("2026-10-21")
        self.assertNotEqual(a, b)
        self.assertEqual(list(handler._salts), ["2026-10-21"])  # yesterday's is forgotten in memory

    def test_salt_race_uses_the_winner(self):
        winner = {"PK": {"S": "SALT#2026-10-20"}, "salt": {"S": "w" * 64}}
        real_get = self.ddb.get_item
        calls = []

        def get_item(**kw):
            calls.append(1)
            if len(calls) == 1:
                self.ddb.items[("dev-site-analytics-state", "SALT#2026-10-20", None)] = winner
                return {}
            return real_get(**kw)

        self.ddb.get_item = get_item
        self.assertEqual(handler.get_salt("2026-10-20"), "w" * 64)

    def test_same_visitor_same_day_one_hash_new_day_new_hash(self):
        handler.ingest(event({"t": "pv", "p": "/"}), NOW)
        handler.ingest(event({"t": "pv", "p": "/catering"}), NOW.replace(hour=15))
        handler.ingest(event({"t": "pv", "p": "/"}), NOW.replace(day=21))
        v = [r["v"]["S"] for r in sorted(self.raw(), key=lambda r: r["SK"]["S"])]
        self.assertEqual(v[0], v[1])
        self.assertNotEqual(v[1], v[2])

    def test_rollup_deletes_past_salts(self):
        handler.get_salt("2026-10-19")
        handler.rollup({}, NOW)
        self.assertIn("SALT#2026-10-19", self.ddb.deleted)
        self.assertNotIn("SALT#2026-10-20", self.ddb.deleted)
        self.assertNotIn(("dev-site-analytics-state", "SALT#2026-10-19", None), self.ddb.items)


class IngestTest(Base):
    def test_stores_no_ip_and_no_user_agent(self):
        resp = handler.ingest(event({"t": "pv", "p": "/catering.html", "r": "www.google.se", "w": "d", "l": "sv-SE",
                                     "us": "Facebook", "um": "cpc", "uc": "Höst"}), NOW)
        self.assertEqual(resp["statusCode"], 204)
        [item] = self.raw()
        flat = json.dumps(item)
        self.assertNotIn("203.0.113.7", flat)
        self.assertNotIn("Mozilla", flat)
        self.assertEqual(item["PK"]["S"], "RAW#2026-10-20")
        self.assertEqual(item["p"]["S"], "/catering")
        self.assertEqual(item["r"]["S"], "google.se")
        self.assertEqual(item["us"]["S"], "facebook")
        self.assertEqual(item["uc"]["S"], "höst")
        self.assertEqual(item["l"]["S"], "sv")
        self.assertEqual((item["dv"]["S"], item["br"]["S"], item["os"]["S"]), ("desktop", "Chrome", "Windows"))
        self.assertEqual((item["cc"]["S"], item["rg"]["S"], item["ci"]["S"]), ("SE", "Stockholms län", "Stockholm"))
        self.assertEqual(int(item["expiresAt"]["N"]), int(NOW.timestamp()) + 30 * 86400)

    def test_gpc_and_dnt_are_not_counted(self):
        for extra in ({"sec-gpc": "1"}, {"dnt": "1"}):
            resp = handler.ingest(event({"t": "pv", "p": "/"}, headers(**extra)), NOW)
            self.assertEqual(resp["statusCode"], 204)
        self.assertEqual(self.raw(), [])

    def test_bots_are_dropped(self):
        for ua in ("Googlebot/2.1 (+http://www.google.com/bot.html)", "curl/8.4.0", "python-requests/2.32",
                   "Mozilla/5.0 (X11; Linux x86_64) HeadlessChrome/130.0 Safari/537.36", "", "x" * 600,
                   "facebookexternalhit/1.1", "Mozilla/5.0 (compatible; GPTBot/1.2)"):
            self.assertTrue(handler.is_bot(headers(ua)), ua)
        no_fetch_metadata = headers()
        del no_fetch_metadata["sec-fetch-site"]
        self.assertTrue(handler.is_bot(no_fetch_metadata))
        self.assertTrue(handler.is_bot(headers(**{"sec-fetch-site": "cross-site"})))
        self.assertFalse(handler.is_bot(headers()))
        self.assertFalse(handler.is_bot(headers(IPHONE)))
        handler.ingest(event({"t": "pv", "p": "/"}, headers("curl/8.4.0")), NOW)
        self.assertEqual(self.raw(), [])

    def test_validation(self):
        bad = [{"t": "pv"}, {"t": "xx", "p": "/"}, {"t": "pv", "p": "https://evil"}, {"t": "pv", "p": "/", "email": "a"},
               {"t": "pv", "p": "/", "r": "not a host"}, {"t": "pv", "p": "/", "w": "huge"},
               {"t": "en", "p": "/", "s": "99999"}, {"t": "en", "p": "/", "d": "33"}, {"t": "ev", "p": "/", "e": "buy"},
               {"t": "ev", "p": "/", "e": "cta", "n": "Anna Berg <a@b.se>"}, {"t": "pv", "p": "/", "us": "x\x01y"}]
        for params in bad:
            self.assertEqual(handler.ingest(event(params), NOW)["statusCode"], 400, params)
        self.assertEqual(handler.ingest(event({"t": "pv", "p": "/"}, method="POST"), NOW)["statusCode"], 405)
        self.assertEqual(self.raw(), [])

    def test_own_site_is_not_a_referrer(self):
        self.assertNotIn("r", handler.validate({"t": "pv", "p": "/", "r": "dev.booqy.se"}))
        self.assertNotIn("r", handler.validate({"t": "pv", "p": "/", "r": "www.dev.booqy.se"}))

    def test_paths_are_normalized(self):
        for raw, want in (("/", "/"), ("/index.html", "/"), ("/Catering.html", "/catering"), ("/demo/", "/demo"),
                          ("/demo?dag=2026-10-21", "/demo")):
            self.assertEqual(handler.normalize_path(raw), want)

    def test_rate_limit_per_visitor(self):
        for _ in range(handler.RATE_MAX + 5):
            handler.ingest(event({"t": "ev", "p": "/", "e": "cta", "n": "/demo"}), NOW)
        self.assertEqual(len(self.raw()), handler.RATE_MAX)

    def test_families(self):
        self.assertEqual((handler.browser_family(IPHONE), handler.os_family(IPHONE), handler.device_of(None, IPHONE)),
                         ("Safari", "iOS", "mobile"))
        edge = CHROME + " Edg/130.0"
        self.assertEqual(handler.browser_family(edge), "Edge")
        android = "Mozilla/5.0 (Linux; Android 14) AppleWebKit/537.36 Chrome/130 Mobile Safari/537.36"
        self.assertEqual(handler.os_family(android), "Android")
        self.assertEqual(handler.device_of("t", CHROME), "tablet")


class ClassifyTest(unittest.TestCase):
    def test_sources(self):
        c = handler.classify
        self.assertEqual(c(None, {}), "direct")
        self.assertEqual(c("google.se", {}), "search")
        self.assertEqual(c("bing.com", {}), "search")
        self.assertEqual(c("duckduckgo.com", {}), "search")
        self.assertEqual(c("mail.google.com", {}), "referral")
        self.assertEqual(c("l.facebook.com", {}), "social")
        self.assertEqual(c("linkedin.com", {}), "social")
        self.assertEqual(c("t.co", {}), "social")
        self.assertEqual(c("restaurangvarlden.se", {}), "referral")
        self.assertEqual(c("google.se", {"us": "newsletter"}), "campaign")
        self.assertEqual(c(None, {"uc": "host"}), "campaign")
        self.assertEqual(c(None, {"ut": "only-term"}), "direct")


def hit(v, minute, t="pv", p="/", **kw):
    return {"v": v, "ts": int(NOW.timestamp() * 1000) + minute * 60_000, "t": t, "p": p, **kw}


class AggregateTest(unittest.TestCase):
    def test_visits_bounces_and_conversions(self):
        hits = [
            # a: lands from Google, reads, books a demo
            hit("a", 0, r="google.se", cc="SE", rg="Stockholms län", ci="Stockholm", dv="mobile", br="Safari", os="iOS", l="sv"),
            hit("a", 1, t="en", s=40, d=75),
            hit("a", 2, p="/demo"),
            hit("a", 3, t="ev", p="/demo", e="demo"),
            hit("a", 4, t="en", p="/demo", s=30, d=100),
            # a again 2 hours later: a new visit, direct, bounced
            hit("a", 120, cc="SE", dv="mobile"),
            # b: campaign visit, one page, short: a bounce
            hit("b", 5, p="/catering", us="facebook", um="paid", uc="host", ux="video", cc="NO", dv="desktop"),
            hit("b", 6, t="en", p="/catering", s=4, d=25),
            hit("b", 6, t="ev", p="/catering", e="cta", n="/demo"),
            # engagement without a page view (just after midnight): ignored
            hit("c", 7, t="en", s=50, d=100),
        ]
        s = handler.build_stats(hits)
        self.assertEqual((s["visitors"], s["visits"], s["pageviews"]), (2, 3, 4))
        self.assertEqual((s["conversions"], s["convertedVisits"]), (1, 1))
        self.assertEqual(s["bounces"], 2)  # a's second visit, and b: one page, 4 s (a CTA click is not engagement)
        self.assertEqual(s["engagedSeconds"], 74)
        self.assertEqual(s["sources"]["search"], {"v": 1, "c": 1, "b": 0})
        self.assertEqual(s["sources"]["direct"], {"v": 1, "c": 0, "b": 1})
        self.assertEqual(s["sources"]["campaign"]["v"], 1)
        self.assertEqual(s["campaigns"], {"facebook|paid|host": {"v": 1, "c": 0, "b": 1}})
        self.assertEqual(s["contents"], {"video": {"v": 1, "c": 0, "b": 1}})
        self.assertEqual(s["landing"]["/"], {"v": 2, "c": 1, "b": 1})
        self.assertEqual(s["pages"]["/demo"], {"pv": 1, "s": 30, "n": 1})
        self.assertEqual(s["countries"]["SE"]["v"], 2)
        self.assertEqual(s["regions"], {"SE|Stockholms län": {"v": 1, "c": 1, "b": 0}})
        self.assertEqual(s["devices"]["mobile"]["v"], 2)
        self.assertEqual(s["scroll"], {"0": 0, "25": 1, "50": 0, "75": 1, "100": 1})
        self.assertEqual(s["events"]["cta"], {"/demo": 1})
        self.assertEqual(s["referrers"], {"google.se": {"v": 1, "c": 1, "b": 0}})
        self.assertEqual(sum(s["hours"]), 3)
        self.assertEqual(s["hours"][11], 2)  # 09:30 UTC is 11:30 in Stockholm (CEST)

    def test_campaign_b_is_a_bounce_without_the_cta(self):
        s = handler.build_stats([hit("b", 0, us="x"), hit("b", 1, t="en", s=3, d=0)])
        self.assertEqual(s["bounces"], 1)

    def test_big_tables_are_cut(self):
        s = handler.build_stats([hit(f"v{i}", i % 25, p=f"/p{i}", r=f"site{i}.se") for i in range(300)])
        self.assertEqual(len(s["referrers"]), handler.TOP_N)
        self.assertLess(len(json.dumps(s)), 200_000)


class RollupTest(Base):
    def test_rollup_writes_today_and_yesterday(self):
        handler.ingest(event({"t": "pv", "p": "/"}), NOW)
        handler.ingest(event({"t": "en", "p": "/", "s": "12", "d": "50"}), NOW)
        result = handler.rollup({}, NOW)
        self.assertEqual(result["days"]["2026-10-20"], {"visits": 1, "pageviews": 1})
        agg = self.ddb.items[("dev-site-analytics", "AGG", "DAY#2026-10-20")]
        stats = json.loads(agg["stats"]["S"])
        self.assertEqual(stats["engagedSeconds"], 12)
        self.assertIn(("dev-site-analytics", "AGG", "DAY#2026-10-19"), self.ddb.items)
        self.assertIn(("dev-site-analytics", "JOB", "latest"), self.ddb.items)

    def test_rollup_rejects_too_many_days(self):
        with self.assertRaises(ValueError):
            handler.rollup({"days": ["2026-10-01"] * 40}, NOW)


class StockholmTest(unittest.TestCase):
    def test_dst(self):
        f = handler.stockholm_day
        self.assertEqual(f(datetime(2026, 10, 24, 22, 30, tzinfo=timezone.utc)), "2026-10-25")  # CEST, +2
        self.assertEqual(f(datetime(2026, 10, 25, 22, 30, tzinfo=timezone.utc)), "2026-10-25")  # CET, +1
        self.assertEqual(f(datetime(2026, 10, 25, 23, 0, tzinfo=timezone.utc)), "2026-10-26")
        self.assertEqual(handler.stockholm(datetime(2026, 3, 29, 0, 59, tzinfo=timezone.utc)).hour, 1)
        self.assertEqual(handler.stockholm(datetime(2026, 3, 29, 1, 0, tzinfo=timezone.utc)).hour, 3)
        self.assertEqual(handler.stockholm(datetime(2026, 12, 31, 23, 30, tzinfo=timezone.utc)).date().isoformat(),
                         "2027-01-01")


if __name__ == "__main__":
    unittest.main()
