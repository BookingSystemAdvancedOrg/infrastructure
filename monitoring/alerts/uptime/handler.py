"""uptime-check

TRIGGER:
    EventBridge rule, every 5 minutes (monitoring/alerts/uptime.tf)

PURPOSE:
    Load the customer site, the admin app and GET /site-config, and report
    each check as a CloudWatch metric: Booqy/Uptime CheckFailed, dimension
    Check=<name>, 0 when the URL answered the expected status with the
    expected text in the body, 1 otherwise. The alarms on those metrics are
    what email the alerts topic; this function never notifies anyone itself.

ENV_VARS:
    CHECKS            JSON list of {name, url, expect_status, expect_body}
    METRIC_NAMESPACE  Booqy/Uptime
    ENVIRONMENT       dev | prod (logged only)
"""

import json
import os
import urllib.error
import urllib.request

TIMEOUT_SECONDS = 10
USER_AGENT = "booqy-uptime-check/1"


def fetch(url):
    """Return (status, body) for a GET of url; HTTP errors are results, not exceptions."""
    request = urllib.request.Request(url, headers={"User-Agent": USER_AGENT, "Accept": "*/*"})
    try:
        with urllib.request.urlopen(request, timeout=TIMEOUT_SECONDS) as response:
            return response.status, response.read(200_000).decode("utf-8", "replace")
    except urllib.error.HTTPError as error:
        return error.code, error.read(200_000).decode("utf-8", "replace")


def run_check(check):
    """One check -> dict with ok (bool) and what was seen, never raises."""
    name, url = check["name"], check["url"]
    expect_status = int(check.get("expect_status", 200))
    expect_body = check.get("expect_body") or ""
    try:
        status, body = fetch(url)
    except Exception as error:  # DNS, TLS, timeout, connection refused
        return {"name": name, "url": url, "ok": False, "status": None, "error": f"{type(error).__name__}: {error}"}
    ok = status == expect_status and expect_body in body
    result = {"name": name, "url": url, "ok": ok, "status": status}
    if not ok:
        result["error"] = (
            f"expected {expect_status} with {expect_body!r} in the body, "
            f"got {status} and the text {'was' if expect_body in body else 'was not'} there"
        )
        result["body"] = body[:300]
    return result


def publish(namespace, results):
    import boto3  # the Lambda runtime has it; the unit tests patch this function

    boto3.client("cloudwatch").put_metric_data(
        Namespace=namespace,
        MetricData=[
            {
                "MetricName": "CheckFailed",
                "Dimensions": [{"Name": "Check", "Value": r["name"]}],
                "Value": 0 if r["ok"] else 1,
                "Unit": "Count",
            }
            for r in results
        ],
    )


def handler(event, context):
    checks = json.loads(os.environ.get("CHECKS") or "[]")
    results = [run_check(c) for c in checks]
    if results:
        publish(os.environ.get("METRIC_NAMESPACE", "Booqy/Uptime"), results)
    failed = [r["name"] for r in results if not r["ok"]]
    print(json.dumps({"environment": os.environ.get("ENVIRONMENT"), "failed": failed, "results": results}))
    return {"failed": failed, "checked": len(results)}
