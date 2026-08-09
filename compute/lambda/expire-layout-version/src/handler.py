"""ExpireLayoutVersionFn — placeholder handler.

This is a bootstrap stub, not the real implementation: it exists so the
container image has something deployable to point at while the actual
cutover logic gets built out (conditionally write isCurrent = false on the
old version, keyed off the EventBridge Schedule payload, conditional on it
still being the target version for idempotency/safety). Replace this with
the real handler; the Terraform module (main.tf in this directory) doesn't
need to change when that happens, as long as the container's CMD stays
handler.handler.
"""

import json


def handler(event, context):
    print(f"ExpireLayoutVersionFn invoked with event: {json.dumps(event)}")

    return {
        "statusCode": 501,
        "body": json.dumps({
            "message": "ExpireLayoutVersionFn is not implemented yet.",
        }),
    }
