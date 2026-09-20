"""ListLayoutVersionFn — handles the active public layout and internal version listing.

Routes handled:
  GET /locations/{locationId}/layout/active    (NONE auth — customer-facing site)
  GET /locations/{locationId}/layout/versions  (JWT  — internal/staff, not yet implemented)
"""

import json
import os

import boto3
from boto3.dynamodb.conditions import Key

_dynamo = boto3.resource("dynamodb")
_table = _dynamo.Table(os.environ["PUBLISHED_LAYOUT_SNAPSHOT_TABLE_NAME"])

# Floor-plan element fields the customer site renders. Version numbers,
# audit timestamps, and isCurrent are internal state — excluded so the
# response contains nothing the renderer doesn't need.
_ELEMENT_FIELDS = {"walls", "tables", "doors", "windows"}


def handler(event, context):
    print(f"ListLayoutVersionFn invoked with event: {json.dumps(event)}")

    route_key = event.get("routeKey", "")
    path_params = event.get("pathParameters") or {}

    if route_key == "GET /locations/{locationId}/layout/active":
        return _get_active_layout(path_params.get("locationId"))

    # All other routes are not yet implemented.
    return {
        "statusCode": 501,
        "headers": {"Content-Type": "application/json"},
        "body": json.dumps({"message": "ListLayoutVersionFn is not implemented yet."}),
    }


def _get_active_layout(location_id):
    if not location_id:
        return _error(400, "locationId is required")

    # Query all versions for this location. At this scale (a handful of
    # published versions per restaurant) a filter-after-read is cheaper and
    # simpler than a GSI on isCurrent — the table schema deliberately avoids
    # that GSI (see storage/dynamodb/published-layout-snapshot/main.tf).
    response = _table.query(
        KeyConditionExpression=(
            Key("PK").eq(f"LOCATION#{location_id}")
            & Key("SK").begins_with("LAYOUT#")
        )
    )

    active = next(
        (item for item in response.get("Items", []) if item.get("isCurrent") is True),
        None,
    )

    if not active:
        return _error(404, "No active layout found for this location")

    # Strip everything except the floor-plan elements — version numbers,
    # isCurrent, expiresAt, and any audit fields stay server-side.
    elements = {k: active[k] for k in _ELEMENT_FIELDS if k in active}

    return {
        "statusCode": 200,
        "headers": {"Content-Type": "application/json"},
        "body": json.dumps(elements),
    }


def _error(status, message):
    return {
        "statusCode": status,
        "headers": {"Content-Type": "application/json"},
        "body": json.dumps({"message": message}),
    }
