"""GetAvailabilityFn — placeholder handler.

This is a bootstrap stub, not the real implementation: it exists so the
container image has something deployable to point at while the actual
business logic gets built out. Replace this with the real handler; the
Terraform module (main.tf in this directory) doesn't need to change when
that happens, as long as the container's CMD stays handler.handler.
"""

import json


def handler(event, context):
    print(f"GetAvailabilityFn invoked with event: {json.dumps(event)}")

    return {
        "statusCode": 501,
        "body": json.dumps({
            "message": "GetAvailabilityFn is not implemented yet.",
        }),
    }
