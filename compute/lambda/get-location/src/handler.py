"""GetLocationFn — handles public location info and internal location reads.

Routes handled:
  GET /locations/{locationId}/public-info  (NONE auth — customer-facing site)
  GET /locations/{locationId}              (JWT  — internal/staff, not yet implemented)
  GET /locations                           (JWT  — internal/staff, not yet implemented)
"""

import json
import os

import boto3
from boto3.dynamodb.conditions import Key

_dynamo = boto3.resource("dynamodb")
_table = _dynamo.Table(os.environ["LOCATION_TABLE_NAME"])

# Fields the customer site is allowed to see. createdBy, gracePeriodHours,
# and any other internal/operational fields are deliberately excluded so
# this response can be cached and served publicly without leaking admin data.
_PUBLIC_FIELDS = {"name", "address", "phone", "email", "openingHours"}


def handler(event, context):
    print(f"GetLocationFn invoked with event: {json.dumps(event)}")

    route_key = event.get("routeKey", "")
    path_params = event.get("pathParameters") or {}

    if route_key == "GET /locations/{locationId}/public-info":
        return _get_public_info(path_params.get("locationId"))

    # All other routes are not yet implemented.
    return {
        "statusCode": 501,
        "headers": {"Content-Type": "application/json"},
        "body": json.dumps({"message": "GetLocationFn is not implemented yet."}),
    }


def _get_public_info(location_id):
    if not location_id:
        return _error(400, "locationId is required")

    response = _table.get_item(
        Key={"PK": "PLATFORM", "SK": f"LOCATION#{location_id}"},
        # Only project the public fields — no point fetching internal
        # attributes over the wire just to discard them here.
        ProjectionExpression=", ".join(_PUBLIC_FIELDS),
    )

    item = response.get("Item")
    if not item:
        return _error(404, "Location not found")

    return {
        "statusCode": 200,
        "headers": {"Content-Type": "application/json"},
        "body": json.dumps(item),
    }


def _error(status, message):
    return {
        "statusCode": status,
        "headers": {"Content-Type": "application/json"},
        "body": json.dumps({"message": message}),
    }
