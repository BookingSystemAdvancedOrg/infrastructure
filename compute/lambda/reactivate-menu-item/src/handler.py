"""ReactivateMenuItemFn — placeholder handler.

This is a bootstrap stub, not the real implementation: it exists so the
container image has something deployable to point at while the actual
logic gets built out (conditionally write active = true on the menu item
named in the EventBridge Schedule payload, guarded with
attribute_exists(PK) so a schedule that outlives a deleted menu item is a
no-op instead of an error). Replace this with the real handler; the
Terraform module (main.tf in this directory) doesn't need to change when
that happens, as long as the container's CMD stays handler.handler.
"""

import json


def handler(event, context):
    print(f"ReactivateMenuItemFn invoked with event: {json.dumps(event)}")

    return {
        "statusCode": 501,
        "body": json.dumps({
            "message": "ReactivateMenuItemFn is not implemented yet.",
        }),
    }
