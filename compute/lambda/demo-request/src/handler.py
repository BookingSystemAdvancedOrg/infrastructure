"""Demo requests from the public site (booqy.se/demo) -> one email to sales.

CloudFront (landing distribution, path /api/demo-request) forwards the POST
to this function's URL, signed with OAC - the URL itself refuses anything
that doesn't come through that distribution. The browser sends JSON:

  {"date": "2026-10-21", "time": "10:30", "firstName": "...", "lastName": "...",
   "email": "...", "company": "...", "phone": "...", "message": "...",
   "website": "", "elapsedMs": 41230}

"website" is a honeypot (hidden field, humans leave it empty) and elapsedMs
is how long the form was open - a filled honeypot or a form sent within
3 seconds is answered 200 like any other request and silently dropped, so a
bot learns nothing.

The email goes to DEMO_RECIPIENT with Reply-To set to the person who asked,
so answering it is just pressing Reply. No dependencies beyond boto3.
"""

import base64
import html
import json
import logging
import os
import re
from datetime import date, datetime, timedelta, timezone

import boto3

log = logging.getLogger()
log.setLevel(logging.INFO)

try:
    from zoneinfo import ZoneInfo

    STOCKHOLM = ZoneInfo("Europe/Stockholm")
except Exception:  # pragma: no cover - no tz database: close enough for a date check
    STOCKHOLM = timezone(timedelta(hours=1))

RECIPIENT = os.environ.get("DEMO_RECIPIENT", "")
FROM_ADDRESS = os.environ.get("FROM_ADDRESS", "")
ENVIRONMENT = os.environ.get("ENVIRONMENT", "prod")

MAX_DAYS_AHEAD = 60
EARLIEST, LATEST = "08:00", "17:00"
MIN_ELAPSED_MS = 3000

EMAIL_RE = re.compile(r"^[^\s@<>,;\"]{1,64}@[A-Za-z0-9.-]{1,253}\.[A-Za-z]{2,24}$")
TIME_RE = re.compile(r"^([01]\d|2[0-3]):([0-5]\d)$")
PHONE_RE = re.compile(r"^[0-9+()\-\s]{6,24}$")

FIELDS = {  # name: (label in the email, max length, required)
    "firstName": ("Förnamn", 80, True),
    "lastName": ("Efternamn", 80, True),
    "email": ("E-post", 254, True),
    "company": ("Företag", 120, True),
    "phone": ("Telefon", 24, False),
    "message": ("Behov", 2000, False),
}

WEEKDAYS = ["måndag", "tisdag", "onsdag", "torsdag", "fredag", "lördag", "söndag"]
MONTHS = ["januari", "februari", "mars", "april", "maj", "juni", "juli", "augusti",
          "september", "oktober", "november", "december"]

_ses = None


def ses():
    global _ses
    if _ses is None:
        _ses = boto3.client("sesv2")
    return _ses


def respond(status, body):
    return {
        "statusCode": status,
        "headers": {"Content-Type": "application/json", "Cache-Control": "no-store"},
        "body": json.dumps(body),
    }


def clean(value, limit, multiline=False):
    if not isinstance(value, str):
        return ""
    value = value.replace("\r\n", "\n").replace("\r", "\n").strip()
    if not multiline:
        value = " ".join(value.split())  # no newlines in a header / subject line
    # drop control characters except newline
    value = "".join(ch for ch in value if ch == "\n" or ord(ch) >= 32)
    return value[:limit]


def today_stockholm():
    return datetime.now(STOCKHOLM).date()


def validate(data):
    """Returns (cleaned fields, {field: error}). Errors are Swedish, shown under the field."""
    out, errors = {}, {}
    for name, (_, limit, required) in FIELDS.items():
        value = clean(data.get(name), limit, multiline=(name == "message"))
        if required and not value:
            errors[name] = "Fyll i fältet."
        out[name] = value

    if out["email"] and not EMAIL_RE.match(out["email"]):
        errors["email"] = "Ange en giltig e-postadress."
    if out["phone"] and not PHONE_RE.match(out["phone"]):
        errors["phone"] = "Ange ett giltigt telefonnummer."

    try:
        day = date.fromisoformat(clean(data.get("date"), 10))
    except ValueError:
        day = None
    today = today_stockholm()
    if day is None:
        errors["date"] = "Välj en dag."
    elif day <= today or day > today + timedelta(days=MAX_DAYS_AHEAD) or day.weekday() >= 5:
        errors["date"] = "Välj en vardag de närmaste veckorna."
    out["date"] = day

    time = clean(data.get("time"), 5)
    if not TIME_RE.match(time) or not (EARLIEST <= time <= LATEST):
        errors["time"] = "Välj en tid."
    out["time"] = time
    return out, errors


def swedish_date(day):
    return f"{WEEKDAYS[day.weekday()]} {day.day} {MONTHS[day.month - 1]} {day.year}"


def build_email(f, source_ip):
    when = f"{swedish_date(f['date'])} kl. {f['time']}"
    name = f"{f['firstName']} {f['lastName']}"
    prefix = "" if ENVIRONMENT == "prod" else f"[{ENVIRONMENT}] "
    subject = f"{prefix}Demoförfrågan: {f['company']} – {f['date'].isoformat()} {f['time']}"

    rows = [
        ("Önskad tid", f"{when} (svensk tid)"),
        ("Namn", name),
        ("Företag", f["company"]),
        ("E-post", f["email"]),
        ("Telefon", f["phone"] or "–"),
    ]
    need = f["message"] or "–"
    sent = datetime.now(STOCKHOLM).strftime("%Y-%m-%d %H:%M")

    text = "\n".join(
        ["Ny demoförfrågan från booqy.se", ""]
        + [f"{label + ':':<12} {value}" for label, value in rows]
        + ["", "Behov:", need, "", "--",
           f"Skickad {sent} från {source_ip or 'okänd IP'}",
           "Svara på det här mejlet för att svara kunden direkt."]
    )

    e = html.escape
    cells = "".join(
        f'<tr><th align="left" style="padding:8px 16px 8px 0;color:#57504d;font-weight:600;'
        f'white-space:nowrap;vertical-align:top">{e(label)}</th>'
        f'<td style="padding:8px 0;color:#1c1918">{e(value)}</td></tr>'
        for label, value in rows
    )
    body_html = f"""<!doctype html><html lang="sv"><body style="margin:0;background:#f1eee6;padding:24px">
<table role="presentation" width="100%" style="max-width:560px;margin:0 auto;background:#fbfaf6;border-collapse:collapse;font:15px/1.5 -apple-system,Segoe UI,Arial,sans-serif;color:#1c1918">
<tr><td style="background:#350001;color:#f6ece9;padding:18px 24px;font-weight:700;font-size:17px">Ny demoförfrågan</td></tr>
<tr><td style="padding:20px 24px 8px">
<p style="margin:0 0 4px;color:#9e1d26;font-weight:700">{e(when)}</p>
<p style="margin:0 0 16px;color:#57504d;font-size:13px">Svensk tid · önskemål, inte bokat än</p>
<table role="presentation" style="border-collapse:collapse;width:100%">{cells}</table>
<p style="margin:18px 0 6px;color:#57504d;font-weight:600">Behov</p>
<p style="margin:0 0 20px;white-space:pre-wrap">{e(need)}</p>
</td></tr>
<tr><td style="padding:14px 24px 20px;border-top:1px dashed #d9d4c8;color:#57504d;font-size:12px">
Skickad {e(sent)} via booqy.se/demo{(' från ' + e(source_ip)) if source_ip else ''}.<br>
Svara på mejlet för att svara {e(f['firstName'])} direkt.</td></tr>
</table></body></html>"""
    return subject, text, body_html


def handler(event, context):
    method = (event.get("requestContext", {}).get("http", {}).get("method") or "").upper()
    if method != "POST":
        return respond(405, {"error": "method_not_allowed"})

    raw = event.get("body") or ""
    if event.get("isBase64Encoded"):
        try:
            raw = base64.b64decode(raw).decode("utf-8")
        except Exception:
            return respond(400, {"error": "invalid_body"})
    if len(raw) > 10_000:
        return respond(413, {"error": "too_large"})
    try:
        data = json.loads(raw)
    except ValueError:
        return respond(400, {"error": "invalid_json"})
    if not isinstance(data, dict):
        return respond(400, {"error": "invalid_json"})

    # Bots: same answer as a real request, nothing sent.
    elapsed = data.get("elapsedMs")
    if clean(data.get("website"), 200) or not isinstance(elapsed, (int, float)) or elapsed < MIN_ELAPSED_MS:
        log.info(json.dumps({"event": "demo_request_dropped", "honeypot": bool(data.get("website"))}))
        return respond(200, {"ok": True})

    fields, errors = validate(data)
    if errors:
        return respond(422, {"error": "invalid", "fields": errors})

    headers = {k.lower(): v for k, v in (event.get("headers") or {}).items()}
    # Behind CloudFront the function URL sees CloudFront's IP; the viewer's is
    # the first entry of X-Forwarded-For.
    source_ip = clean((headers.get("x-forwarded-for") or "").split(",")[0], 45)
    subject, text, body_html = build_email(fields, source_ip)

    try:
        ses().send_email(
            FromEmailAddress=f"Booqy webbplats <{FROM_ADDRESS}>",
            Destination={"ToAddresses": [RECIPIENT]},
            ReplyToAddresses=[fields["email"]],
            Content={"Simple": {
                "Subject": {"Data": subject, "Charset": "UTF-8"},
                "Body": {"Text": {"Data": text, "Charset": "UTF-8"},
                         "Html": {"Data": body_html, "Charset": "UTF-8"}},
            }},
        )
    except Exception:
        log.exception("demo request email failed")
        return respond(502, {"error": "send_failed"})

    log.info(json.dumps({"event": "demo_request_sent", "date": fields["date"].isoformat(), "time": fields["time"]}))
    return respond(200, {"ok": True})
