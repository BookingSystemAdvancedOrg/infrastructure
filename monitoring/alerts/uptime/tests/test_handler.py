"""Run: python3 -m unittest discover -s monitoring/alerts/uptime/tests"""

import io
import json
import os
import sys
import unittest
import urllib.error
from unittest import mock

sys.path.insert(0, os.path.join(os.path.dirname(__file__), ".."))

import handler  # noqa: E402


def check(name="site", url="https://example.test/", expect_status=200, expect_body='id="root"'):
    return {"name": name, "url": url, "expect_status": expect_status, "expect_body": expect_body}


class FakeResponse(io.BytesIO):
    def __init__(self, status, body):
        super().__init__(body.encode())
        self.status = status

    def __enter__(self):
        return self

    def __exit__(self, *args):
        self.close()


class RunCheckTest(unittest.TestCase):
    def test_ok_when_status_and_body_match(self):
        with mock.patch.object(handler.urllib.request, "urlopen", return_value=FakeResponse(200, '<div id="root"></div>')):
            result = handler.run_check(check())
        self.assertTrue(result["ok"])
        self.assertEqual(result["status"], 200)

    def test_fails_when_expected_text_is_missing(self):
        with mock.patch.object(handler.urllib.request, "urlopen", return_value=FakeResponse(200, "<html>placeholder</html>")):
            result = handler.run_check(check())
        self.assertFalse(result["ok"])
        self.assertIn("was not there", result["error"])

    def test_http_error_is_a_status_not_an_exception(self):
        error = urllib.error.HTTPError("https://example.test/", 503, "Service Unavailable", {}, io.BytesIO(b"down"))
        with mock.patch.object(handler.urllib.request, "urlopen", side_effect=error):
            result = handler.run_check(check())
        self.assertFalse(result["ok"])
        self.assertEqual(result["status"], 503)

    def test_expected_404_counts_as_ok(self):
        error = urllib.error.HTTPError("https://api.test/site-config", 404, "Not Found", {}, io.BytesIO(b'{"error":"not found"}'))
        with mock.patch.object(handler.urllib.request, "urlopen", side_effect=error):
            result = handler.run_check(check(expect_status=404, expect_body="not found"))
        self.assertTrue(result["ok"])

    def test_connection_failure_is_reported_not_raised(self):
        with mock.patch.object(handler.urllib.request, "urlopen", side_effect=OSError("name resolution failed")):
            result = handler.run_check(check())
        self.assertFalse(result["ok"])
        self.assertIsNone(result["status"])
        self.assertIn("OSError", result["error"])


class HandlerTest(unittest.TestCase):
    def test_publishes_one_metric_per_check_and_lists_failures(self):
        checks = [check("good"), check("bad", url="https://bad.test/")]
        env = {"CHECKS": json.dumps(checks), "METRIC_NAMESPACE": "Booqy/Uptime"}

        def urlopen(request, timeout):
            body = '<div id="root">' if "bad" not in request.full_url else "nope"
            return FakeResponse(200, body)

        with mock.patch.dict(os.environ, env), \
                mock.patch.object(handler.urllib.request, "urlopen", side_effect=urlopen), \
                mock.patch.object(handler, "publish") as publish:
            out = handler.handler({}, None)

        self.assertEqual(out, {"failed": ["bad"], "checked": 2})
        namespace, results = publish.call_args.args
        self.assertEqual(namespace, "Booqy/Uptime")
        self.assertEqual([(r["name"], r["ok"]) for r in results], [("good", True), ("bad", False)])

    def test_no_checks_publishes_nothing(self):
        with mock.patch.dict(os.environ, {"CHECKS": "[]"}), mock.patch.object(handler, "publish") as publish:
            out = handler.handler({}, None)
        self.assertEqual(out, {"failed": [], "checked": 0})
        publish.assert_not_called()


if __name__ == "__main__":
    unittest.main()
