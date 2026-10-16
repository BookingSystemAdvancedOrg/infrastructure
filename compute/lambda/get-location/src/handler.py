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
_tenants = _dynamo.Table(os.environ["TENANT_TABLE_NAME"])
# Locations are keyed TENANT#<tenantId> / LOCATION#<locationId>; a public
# route only knows the locationId, so it is resolved through this index.
_location_index = os.environ["LOCATION_ID_INDEX_NAME"]

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

    response = _table.query(
        IndexName=_location_index,
        KeyConditionExpression=Key("locationId").eq(location_id),
        Limit=1,
    )
    items = response.get("Items") or []
    item = items[0] if items else None
    if not item:
        return _error(404, "Location not found")

    # A location of a suspended or offboarded tenant is not public anymore -
    # same 404 as a location that doesn't exist, so nothing leaks either way.
    tenant = _tenants.get_item(
        Key={"PK": f"TENANT#{item.get('tenantId', '')}", "SK": "PROFILE"},
        ProjectionExpression="#s",
        ExpressionAttributeNames={"#s": "status"},
    ).get("Item")
    if not tenant or tenant.get("status") != "active":
        return _error(404, "Location not found")

    # Filtered here rather than with ProjectionExpression: "name" is a
    # DynamoDB reserved word and would need an alias per field.
    public = {k: v for k, v in item.items() if k in _PUBLIC_FIELDS}
    return {
        "statusCode": 200,
        "headers": {"Content-Type": "application/json"},
        "body": json.dumps(public, default=str),
    }


def _error(status, message):
    return {
        "statusCode": status,
        "headers": {"Content-Type": "application/json"},
        "body": json.dumps({"message": message}),
    }
