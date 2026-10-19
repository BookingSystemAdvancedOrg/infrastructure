"""Run: python3 -m unittest discover -s compute/lambda/demo-request/tests"""

import base64
import json
import os
import sys
import unittest
from datetime import date, timedelta
from unittest import mock

os.environ.setdefault("DEMO_RECIPIENT", "support@example.se")
os.environ.setdefault("FROM_ADDRESS", "noreply@mail.example.se")
os.environ.setdefault("ENVIRONMENT", "prod")
os.environ.setdefault("AWS_DEFAULT_REGION", "eu-north-1")

sys.path.insert(0, os.path.join(os.path.dirname(__file__), "..", "src"))

import handler  # noqa: E402

TODAY = date(2026, 10, 19)  # a Monday


def next_weekday(days=2):
    d = TODAY + timedelta(days=days)
    while d.weekday() >= 5:
        d += timedelta(days=1)
    return d


def payload(**over):
    body = {
        "date": next_weekday().isoformat(),
        "time": "10:30",
        "firstName": "Anna",
        "lastName": "Berg",
        "email": "anna@restaurang.se",
        "company": "Restaurang Berg AB",
        "phone": "070-123 45 67",
        "message": "Två restauranger, vill ha bordsbokning\noch catering.",
        "website": "",
        "elapsedMs": 40000,
    }
    body.update(over)
    return body


def event(body, method="POST", b64=False, raw=None):
    text = raw if raw is not None else json.dumps(body)
    return {
        "requestContext": {"http": {"method": method}},
        "headers": {"X-Forwarded-For": "203.0.113.7, 130.176.1.1"},
        "body": base64.b64encode(text.encode()).decode() if b64 else text,
        "isBase64Encoded": b64,
    }


class DemoRequestTest(unittest.TestCase):
    def setUp(self):
        self.ses = mock.Mock()
        p1 = mock.patch.object(handler, "ses", return_value=self.ses)
        p2 = mock.patch.object(handler, "today_stockholm", return_value=TODAY)
        p1.start()
        p2.start()
        self.addCleanup(p1.stop)
        self.addCleanup(p2.stop)

    def call(self, ev):
        res = handler.handler(ev, None)
        return res["statusCode"], json.loads(res["body"])

    def test_sends_structured_email_with_reply_to(self):
        status, body = self.call(event(payload()))
        self.assertEqual((status, body), (200, {"ok": True}))
        kw = self.ses.send_email.call_args.kwargs
        self.assertEqual(kw["Destination"], {"ToAddresses": ["support@example.se"]})
        self.assertEqual(kw["ReplyToAddresses"], ["anna@restaurang.se"])
        self.assertEqual(kw["FromEmailAddress"], "Booqy webbplats <noreply@mail.example.se>")
        content = kw["Content"]["Simple"]
        d = next_weekday().isoformat()
        self.assertEqual(content["Subject"]["Data"], f"Demoförfrågan: Restaurang Berg AB – {d} 10:30")
        text = content["Body"]["Text"]["Data"]
        for expected in ["Anna Berg", "Restaurang Berg AB", "anna@restaurang.se", "070-123 45 67",
                         "kl. 10:30", "onsdag", "och catering.", "203.0.113.7"]:
            self.assertIn(expected, text)

    def test_base64_body(self):
        status, _ = self.call(event(payload(), b64=True))
        self.assertEqual(status, 200)
        self.ses.send_email.assert_called_once()

    def test_html_is_escaped_and_subject_single_line(self):
        self.call(event(payload(company="<b>Evil</b>\nBcc: x@y.se", message="<script>x</script>")))
        content = self.ses.send_email.call_args.kwargs["Content"]["Simple"]
        self.assertNotIn("\n", content["Subject"]["Data"])
        html_body = content["Body"]["Html"]["Data"]
        self.assertNotIn("<script>", html_body)
        self.assertIn("&lt;b&gt;Evil&lt;/b&gt;", html_body)

    def test_optional_fields(self):
        status, _ = self.call(event(payload(phone="", message="")))
        self.assertEqual(status, 200)
        self.assertIn("Telefon:     –", self.ses.send_email.call_args.kwargs["Content"]["Simple"]["Body"]["Text"]["Data"])

    def test_required_fields_and_formats(self):
        status, body = self.call(event(payload(firstName=" ", email="not-an-email", phone="abc", company="")))
        self.assertEqual(status, 422)
        self.assertEqual(set(body["fields"]), {"firstName", "email", "phone", "company"})
        self.ses.send_email.assert_not_called()

    def test_date_rules(self):
        saturday = TODAY + timedelta(days=5)
        for bad in [TODAY.isoformat(), (TODAY - timedelta(days=1)).isoformat(), saturday.isoformat(),
                    (TODAY + timedelta(days=90)).isoformat(), "2026-13-01", ""]:
            status, body = self.call(event(payload(date=bad)))
            self.assertEqual(status, 422, bad)
            self.assertIn("date", body["fields"])

    def test_time_rules(self):
        for bad in ["07:30", "17:30", "25:00", "10.30", ""]:
            status, body = self.call(event(payload(time=bad)))
            self.assertEqual(status, 422, bad)
            self.assertIn("time", body["fields"])

    def test_honeypot_and_too_fast_are_dropped_silently(self):
        for over in [{"website": "http://spam"}, {"elapsedMs": 900}, {"elapsedMs": "x"}]:
            status, body = self.call(event(payload(**over)))
            self.assertEqual((status, body), (200, {"ok": True}))
        self.ses.send_email.assert_not_called()

    def test_bad_requests(self):
        self.assertEqual(self.call(event({}, method="GET"))[0], 405)
        self.assertEqual(self.call(event(None, raw="{nope"))[0], 400)
        self.assertEqual(self.call(event(None, raw="[1]"))[0], 400)
        self.assertEqual(self.call(event(None, raw="x" * 20000))[0], 413)

    def test_ses_failure_is_502(self):
        self.ses.send_email.side_effect = RuntimeError("throttled")
        with self.assertLogs(level="ERROR"):
            status, body = self.call(event(payload()))
        self.assertEqual((status, body), (502, {"error": "send_failed"}))

    def test_non_prod_subject_prefix(self):
        with mock.patch.object(handler, "ENVIRONMENT", "dev"):
            self.call(event(payload()))
        self.assertTrue(self.ses.send_email.call_args.kwargs["Content"]["Simple"]["Subject"]["Data"].startswith("[dev] "))


if __name__ == "__main__":
    unittest.main()
