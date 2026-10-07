locals {
  api_name = var.environment == "prod" ? "bsa-api" : "${var.environment}-bsa-api"
}

resource "aws_apigatewayv2_api" "this" {
  name          = local.api_name
  protocol_type = "HTTP"

  # Authorization header is what carries the Cognito JWT - it has to be an
  # allowed header or the browser's preflight OPTIONS request fails before
  # the real request is ever sent.
  #
  # Origins: every tenant website lives on its own domain (restaurant.se,
  # <slug>.<platform_domain>), and tenants are added at runtime - a static
  # origin list would mean a Terraform change per customer. allowed_origins
  # is therefore ["*"] by default, which is safe for THIS API because it
  # never relies on cookies or other ambient credentials: every privileged
  # call carries an explicit bearer token (or the magic-link HMAC header),
  # which a foreign origin can't obtain. allow_credentials stays false, so
  # browsers never attach cookies cross-origin. Authorization is the
  # authorizer + the tenant check in each Lambda, not CORS.
  cors_configuration {
    allow_origins = var.allowed_origins
    allow_methods = ["GET", "POST", "PUT", "PATCH", "DELETE", "OPTIONS"]
    allow_headers = ["authorization", "content-type", "x-order-token"] # x-order-token: catering magic-link HMAC, sent as a header so it never lands in access logs or Referer headers
    max_age       = 300
  }

  tags = {
    Environment = var.environment
  }
}

# HTTP APIs need at least one stage to actually be invocable.
# auto_deploy means route/integration changes go live without a separate
# "create deployment" step - the appropriate choice here since this whole
# API is already only ever changed through Terraform, not the console.
resource "aws_apigatewayv2_stage" "this" {
  api_id      = aws_apigatewayv2_api.this.id
  name        = "$default"
  auto_deploy = true

  tags = {
    Environment = var.environment
  }
}

# The one authorizer every JWT-protected route below points at. Validates
# tokens by fetching the user pool's public signing keys over HTTPS and
# checking the signature locally - no IAM role or AWS-side permission
# needed for this, since nothing privileged is being called (see the notes
# in security/iam/manage-auth for what *does* need real Cognito
# permissions - this isn't that).
resource "aws_apigatewayv2_authorizer" "cognito" {
  api_id           = aws_apigatewayv2_api.this.id
  authorizer_type  = "JWT"
  identity_sources = ["$request.header.Authorization"]
  name             = "cognito-jwt"

  jwt_configuration {
    audience = [var.cognito_client_id]
    issuer   = "https://cognito-idp.${var.region}.amazonaws.com/${var.cognito_user_pool_id}"
  }
}

# Second authorizer, for /platform/* only: tokens from the OPERATOR user pool
# (storage/cognito-platform). A tenant-pool token - even an owner's - is
# rejected here by issuer before any Lambda runs, and each platform route
# additionally requires the platform/admin scope (authorization_scopes).
resource "aws_apigatewayv2_authorizer" "platform" {
  api_id           = aws_apigatewayv2_api.this.id
  authorizer_type  = "JWT"
  identity_sources = ["$request.header.Authorization"]
  name             = "platform-operator-jwt"

  jwt_configuration {
    audience = [var.platform_client_id]
    issuer   = "https://cognito-idp.${var.region}.amazonaws.com/${var.platform_user_pool_id}"
  }
}


# --- get-location ---

resource "aws_apigatewayv2_integration" "get_location" {
  api_id                 = aws_apigatewayv2_api.this.id
  integration_type       = "AWS_PROXY"
  integration_uri        = var.get_location_invoke_arn
  integration_method     = "POST" # Lambda proxy integrations always invoke via POST, regardless of the route's own method
  payload_format_version = "2.0"
}

resource "aws_apigatewayv2_route" "get_location" {
  api_id             = aws_apigatewayv2_api.this.id
  route_key          = "GET /locations/{locationId}"
  target             = "integrations/${aws_apigatewayv2_integration.get_location.id}"
  authorization_type = "JWT"
  authorizer_id      = aws_apigatewayv2_authorizer.cognito.id
}

resource "aws_lambda_permission" "get_location_invoke" {
  statement_id  = "AllowAPIGatewayInvoke"
  action        = "lambda:InvokeFunction"
  function_name = var.get_location_function_name
  principal     = "apigateway.amazonaws.com"
  source_arn    = "${aws_apigatewayv2_api.this.execution_arn}/*/*"
}


# --- get-location ---
#
# Reuses the get-location integration/Lambda above instead of a separate
# function - GetLocationFn already handles the single-location read, and
# its IAM role is already read-only on the location table (Scan/GetItem/
# Query, not dynamodb:*), so no new integration, lambda_permission, or IAM
# change is needed: the existing lambda_permission's source_arn
# ("${execution_arn}/*/*") already covers this route too.

resource "aws_apigatewayv2_route" "list_locations" {
  api_id             = aws_apigatewayv2_api.this.id
  route_key          = "GET /locations"
  target             = "integrations/${aws_apigatewayv2_integration.get_location.id}"
  authorization_type = "JWT"
  authorizer_id      = aws_apigatewayv2_authorizer.cognito.id
}


# --- get-location: public-info ---
#
# Public route — customer-facing site (no auth required). Reuses the
# get_location integration and Lambda so no new function, integration, or
# IAM change is needed: the existing lambda_permission's source_arn
# ("${execution_arn}/*/*") already covers this route. The Lambda branches
# on the routeKey it receives to return only the public-safe fields
# (name, address, phone, email, openingHours) — internal fields such as
# createdBy and gracePeriodHours are never included in the response.

resource "aws_apigatewayv2_route" "get_location_public_info" {
  api_id             = aws_apigatewayv2_api.this.id
  route_key          = "GET /locations/{locationId}/public-info"
  target             = "integrations/${aws_apigatewayv2_integration.get_location.id}"
  authorization_type = "NONE"
}


# --- create-location ---

resource "aws_apigatewayv2_integration" "create_location" {
  api_id                 = aws_apigatewayv2_api.this.id
  integration_type       = "AWS_PROXY"
  integration_uri        = var.create_location_invoke_arn
  integration_method     = "POST" # Lambda proxy integrations always invoke via POST, regardless of the route's own method
  payload_format_version = "2.0"
}

resource "aws_apigatewayv2_route" "create_location" {
  api_id             = aws_apigatewayv2_api.this.id
  route_key          = "POST /locations"
  target             = "integrations/${aws_apigatewayv2_integration.create_location.id}"
  authorization_type = "JWT"
  authorizer_id      = aws_apigatewayv2_authorizer.cognito.id
}

resource "aws_lambda_permission" "create_location_invoke" {
  statement_id  = "AllowAPIGatewayInvoke"
  action        = "lambda:InvokeFunction"
  function_name = var.create_location_function_name
  principal     = "apigateway.amazonaws.com"
  source_arn    = "${aws_apigatewayv2_api.this.execution_arn}/*/*"
}


# --- create-location ---
#
# Reuses the create-location integration/Lambda above instead of a
# separate function - that Lambda already handles both create and
# update, and its IAM role is already dynamodb:*, so no new integration
# or lambda_permission is needed: the existing one's source_arn
# ("${execution_arn}/*/*") already covers this route too.

resource "aws_apigatewayv2_route" "update_location" {
  api_id             = aws_apigatewayv2_api.this.id
  route_key          = "PUT /locations/{locationId}"
  target             = "integrations/${aws_apigatewayv2_integration.create_location.id}"
  authorization_type = "JWT"
  authorizer_id      = aws_apigatewayv2_authorizer.cognito.id
}


# --- get-menu ---

resource "aws_apigatewayv2_integration" "get_menu" {
  api_id                 = aws_apigatewayv2_api.this.id
  integration_type       = "AWS_PROXY"
  integration_uri        = var.get_menu_invoke_arn
  integration_method     = "POST" # Lambda proxy integrations always invoke via POST, regardless of the route's own method
  payload_format_version = "2.0"
}

# Public route — customers (no auth required)
resource "aws_apigatewayv2_route" "get_menu" {
  api_id             = aws_apigatewayv2_api.this.id
  route_key          = "GET /locations/{locationId}/menu"
  target             = "integrations/${aws_apigatewayv2_integration.get_menu.id}"
  authorization_type = "NONE"
}

# Staff route — JWT required; same get_menu Lambda handles both routes and
# uses the routeKey to decide whether to include inactive items.
resource "aws_apigatewayv2_route" "get_menu_staff_and_owner" {
  api_id             = aws_apigatewayv2_api.this.id
  route_key          = "GET /locations/{locationId}/menu/{proxy+}"
  target             = "integrations/${aws_apigatewayv2_integration.get_menu.id}"
  authorization_type = "JWT"
  authorizer_id      = aws_apigatewayv2_authorizer.cognito.id
}

resource "aws_lambda_permission" "get_menu_invoke" {
  statement_id  = "AllowAPIGatewayInvoke"
  action        = "lambda:InvokeFunction"
  function_name = var.get_menu_function_name
  principal     = "apigateway.amazonaws.com"
  source_arn    = "${aws_apigatewayv2_api.this.execution_arn}/*/*"
}


# --- manage-menu ---

resource "aws_apigatewayv2_integration" "manage_menu" {
  api_id                 = aws_apigatewayv2_api.this.id
  integration_type       = "AWS_PROXY"
  integration_uri        = var.manage_menu_invoke_arn
  integration_method     = "POST" # Lambda proxy integrations always invoke via POST, regardless of the route's own method
  payload_format_version = "2.0"
}

# Same ANY-swallows-OPTIONS CORS bug as manage-user, same fix. Per
# LAMBDA_REFERENCE.md ("create/update/delete individual menu items or
# categories") this Lambda is write-only - reads go through the separate
# public get-menu function - so no GET route here. Confirm with whoever
# owns manage-menu before adding one.
locals {
  manage_menu_methods = ["POST", "PUT", "DELETE"]
}

resource "aws_apigatewayv2_route" "manage_menu" {
  for_each = toset(local.manage_menu_methods)

  api_id             = aws_apigatewayv2_api.this.id
  route_key          = "${each.value} /locations/{locationId}/menu/{proxy+}"
  target             = "integrations/${aws_apigatewayv2_integration.manage_menu.id}"
  authorization_type = "JWT"
  authorizer_id      = aws_apigatewayv2_authorizer.cognito.id
}

resource "aws_lambda_permission" "manage_menu_invoke" {
  statement_id  = "AllowAPIGatewayInvoke"
  action        = "lambda:InvokeFunction"
  function_name = var.manage_menu_function_name
  principal     = "apigateway.amazonaws.com"
  source_arn    = "${aws_apigatewayv2_api.this.execution_arn}/*/*"
}


# --- get-availability ---

resource "aws_apigatewayv2_integration" "get_availability" {
  api_id                 = aws_apigatewayv2_api.this.id
  integration_type       = "AWS_PROXY"
  integration_uri        = var.get_availability_invoke_arn
  integration_method     = "POST" # Lambda proxy integrations always invoke via POST, regardless of the route's own method
  payload_format_version = "2.0"
}

resource "aws_apigatewayv2_route" "get_availability" {
  api_id             = aws_apigatewayv2_api.this.id
  route_key          = "GET /locations/{locationId}/availability"
  target             = "integrations/${aws_apigatewayv2_integration.get_availability.id}"
  authorization_type = "NONE"
}

resource "aws_lambda_permission" "get_availability_invoke" {
  statement_id  = "AllowAPIGatewayInvoke"
  action        = "lambda:InvokeFunction"
  function_name = var.get_availability_function_name
  principal     = "apigateway.amazonaws.com"
  source_arn    = "${aws_apigatewayv2_api.this.execution_arn}/*/*"
}


# --- create-pending-reservation ---

resource "aws_apigatewayv2_integration" "create_pending_reservation" {
  api_id                 = aws_apigatewayv2_api.this.id
  integration_type       = "AWS_PROXY"
  integration_uri        = var.create_pending_reservation_invoke_arn
  integration_method     = "POST" # Lambda proxy integrations always invoke via POST, regardless of the route's own method
  payload_format_version = "2.0"
}

resource "aws_apigatewayv2_route" "create_pending_reservation" {
  api_id             = aws_apigatewayv2_api.this.id
  route_key          = "POST /reservations"
  target             = "integrations/${aws_apigatewayv2_integration.create_pending_reservation.id}"
  authorization_type = "NONE"
}

resource "aws_lambda_permission" "create_pending_reservation_invoke" {
  statement_id  = "AllowAPIGatewayInvoke"
  action        = "lambda:InvokeFunction"
  function_name = var.create_pending_reservation_function_name
  principal     = "apigateway.amazonaws.com"
  source_arn    = "${aws_apigatewayv2_api.this.execution_arn}/*/*"
}


# --- get-reservation ---

resource "aws_apigatewayv2_integration" "get_reservation" {
  api_id                 = aws_apigatewayv2_api.this.id
  integration_type       = "AWS_PROXY"
  integration_uri        = var.get_reservation_invoke_arn
  integration_method     = "POST" # Lambda proxy integrations always invoke via POST, regardless of the route's own method
  payload_format_version = "2.0"
}

resource "aws_apigatewayv2_route" "get_reservation" {
  api_id             = aws_apigatewayv2_api.this.id
  route_key          = "GET /reservations/{reservationId}"
  target             = "integrations/${aws_apigatewayv2_integration.get_reservation.id}"
  authorization_type = "JWT"
  authorizer_id      = aws_apigatewayv2_authorizer.cognito.id
}

resource "aws_lambda_permission" "get_reservation_invoke" {
  statement_id  = "AllowAPIGatewayInvoke"
  action        = "lambda:InvokeFunction"
  function_name = var.get_reservation_function_name
  principal     = "apigateway.amazonaws.com"
  source_arn    = "${aws_apigatewayv2_api.this.execution_arn}/*/*"
}


# --- get-order ---

resource "aws_apigatewayv2_integration" "get_order" {
  api_id                 = aws_apigatewayv2_api.this.id
  integration_type       = "AWS_PROXY"
  integration_uri        = var.get_order_invoke_arn
  integration_method     = "POST" # Lambda proxy integrations always invoke via POST, regardless of the route's own method
  payload_format_version = "2.0"
}

resource "aws_apigatewayv2_route" "get_order" {
  api_id             = aws_apigatewayv2_api.this.id
  route_key          = "GET /reservations/{reservationId}/orders/{orderId}"
  target             = "integrations/${aws_apigatewayv2_integration.get_order.id}"
  authorization_type = "JWT"
  authorizer_id      = aws_apigatewayv2_authorizer.cognito.id
}

resource "aws_lambda_permission" "get_order_invoke" {
  statement_id  = "AllowAPIGatewayInvoke"
  action        = "lambda:InvokeFunction"
  function_name = var.get_order_function_name
  principal     = "apigateway.amazonaws.com"
  source_arn    = "${aws_apigatewayv2_api.this.execution_arn}/*/*"
}


# --- payment-intent ---
#
# Public/NONE, same as create-pending-reservation and cancel-reservation -
# customers never have Cognito accounts, so checkout can't sit behind the
# JWT authorizer.

resource "aws_apigatewayv2_integration" "payment_intent" {
  api_id                 = aws_apigatewayv2_api.this.id
  integration_type       = "AWS_PROXY"
  integration_uri        = var.payment_intent_invoke_arn
  integration_method     = "POST" # Lambda proxy integrations always invoke via POST, regardless of the route's own method
  payload_format_version = "2.0"
}

resource "aws_apigatewayv2_route" "payment_intent" {
  api_id             = aws_apigatewayv2_api.this.id
  route_key          = "POST /order"
  target             = "integrations/${aws_apigatewayv2_integration.payment_intent.id}"
  authorization_type = "NONE"
}

resource "aws_lambda_permission" "payment_intent_invoke" {
  statement_id  = "AllowAPIGatewayInvoke"
  action        = "lambda:InvokeFunction"
  function_name = var.payment_intent_function_name
  principal     = "apigateway.amazonaws.com"
  source_arn    = "${aws_apigatewayv2_api.this.execution_arn}/*/*"
}


# --- cancel-reservation ---

resource "aws_apigatewayv2_integration" "cancel_reservation" {
  api_id                 = aws_apigatewayv2_api.this.id
  integration_type       = "AWS_PROXY"
  integration_uri        = var.cancel_reservation_invoke_arn
  integration_method     = "POST" # Lambda proxy integrations always invoke via POST, regardless of the route's own method
  payload_format_version = "2.0"
}

resource "aws_apigatewayv2_route" "cancel_reservation" {
  api_id             = aws_apigatewayv2_api.this.id
  route_key          = "POST /reservations/{reservationId}/cancel"
  target             = "integrations/${aws_apigatewayv2_integration.cancel_reservation.id}"
  authorization_type = "NONE"
}

resource "aws_lambda_permission" "cancel_reservation_invoke" {
  statement_id  = "AllowAPIGatewayInvoke"
  action        = "lambda:InvokeFunction"
  function_name = var.cancel_reservation_function_name
  principal     = "apigateway.amazonaws.com"
  source_arn    = "${aws_apigatewayv2_api.this.execution_arn}/*/*"
}


# --- mark-arrived ---

resource "aws_apigatewayv2_integration" "mark_arrived" {
  api_id                 = aws_apigatewayv2_api.this.id
  integration_type       = "AWS_PROXY"
  integration_uri        = var.mark_arrived_invoke_arn
  integration_method     = "POST" # Lambda proxy integrations always invoke via POST, regardless of the route's own method
  payload_format_version = "2.0"
}

resource "aws_apigatewayv2_route" "mark_arrived" {
  api_id             = aws_apigatewayv2_api.this.id
  route_key          = "POST /reservations/{reservationId}/arrive"
  target             = "integrations/${aws_apigatewayv2_integration.mark_arrived.id}"
  authorization_type = "JWT"
  authorizer_id      = aws_apigatewayv2_authorizer.cognito.id
}

resource "aws_lambda_permission" "mark_arrived_invoke" {
  statement_id  = "AllowAPIGatewayInvoke"
  action        = "lambda:InvokeFunction"
  function_name = var.mark_arrived_function_name
  principal     = "apigateway.amazonaws.com"
  source_arn    = "${aws_apigatewayv2_api.this.execution_arn}/*/*"
}


# --- block-table ---

resource "aws_apigatewayv2_integration" "block_table" {
  api_id                 = aws_apigatewayv2_api.this.id
  integration_type       = "AWS_PROXY"
  integration_uri        = var.block_table_invoke_arn
  integration_method     = "POST" # Lambda proxy integrations always invoke via POST, regardless of the route's own method
  payload_format_version = "2.0"
}

resource "aws_apigatewayv2_route" "block_table" {
  api_id             = aws_apigatewayv2_api.this.id
  route_key          = "POST /locations/{locationId}/tables/{tableId}/block"
  target             = "integrations/${aws_apigatewayv2_integration.block_table.id}"
  authorization_type = "JWT"
  authorizer_id      = aws_apigatewayv2_authorizer.cognito.id
}

resource "aws_lambda_permission" "block_table_invoke" {
  statement_id  = "AllowAPIGatewayInvoke"
  action        = "lambda:InvokeFunction"
  function_name = var.block_table_function_name
  principal     = "apigateway.amazonaws.com"
  source_arn    = "${aws_apigatewayv2_api.this.execution_arn}/*/*"
}


# --- manage-layout-element ---

resource "aws_apigatewayv2_integration" "manage_layout_element" {
  api_id                 = aws_apigatewayv2_api.this.id
  integration_type       = "AWS_PROXY"
  integration_uri        = var.manage_layout_element_invoke_arn
  integration_method     = "POST" # Lambda proxy integrations always invoke via POST, regardless of the route's own method
  payload_format_version = "2.0"
}

# Same ANY-swallows-OPTIONS CORS bug as manage-user, same fix. Per
# LAMBDA_REFERENCE.md this is genuine CRUD ("CRUD on individual floor-plan
# elements") with no separate read function for individual elements, so
# GET is included here (unlike manage-menu, where reads live elsewhere).
locals {
  manage_layout_element_methods = ["GET", "POST", "PUT", "DELETE"]
}

resource "aws_apigatewayv2_route" "manage_layout_element" {
  for_each = toset(local.manage_layout_element_methods)

  api_id             = aws_apigatewayv2_api.this.id
  route_key          = "${each.value} /locations/{locationId}/layout-elements/{proxy+}"
  target             = "integrations/${aws_apigatewayv2_integration.manage_layout_element.id}"
  authorization_type = "JWT"
  authorizer_id      = aws_apigatewayv2_authorizer.cognito.id
}

resource "aws_lambda_permission" "manage_layout_element_invoke" {
  statement_id  = "AllowAPIGatewayInvoke"
  action        = "lambda:InvokeFunction"
  function_name = var.manage_layout_element_function_name
  principal     = "apigateway.amazonaws.com"
  source_arn    = "${aws_apigatewayv2_api.this.execution_arn}/*/*"
}


# --- publish-layout ---

resource "aws_apigatewayv2_integration" "publish_layout" {
  api_id                 = aws_apigatewayv2_api.this.id
  integration_type       = "AWS_PROXY"
  integration_uri        = var.publish_layout_invoke_arn
  integration_method     = "POST" # Lambda proxy integrations always invoke via POST, regardless of the route's own method
  payload_format_version = "2.0"
}

resource "aws_apigatewayv2_route" "publish_layout" {
  api_id             = aws_apigatewayv2_api.this.id
  route_key          = "POST /locations/{locationId}/layout/publish"
  target             = "integrations/${aws_apigatewayv2_integration.publish_layout.id}"
  authorization_type = "JWT"
  authorizer_id      = aws_apigatewayv2_authorizer.cognito.id
}

resource "aws_lambda_permission" "publish_layout_invoke" {
  statement_id  = "AllowAPIGatewayInvoke"
  action        = "lambda:InvokeFunction"
  function_name = var.publish_layout_function_name
  principal     = "apigateway.amazonaws.com"
  source_arn    = "${aws_apigatewayv2_api.this.execution_arn}/*/*"
}


# --- list-layout-version ---

resource "aws_apigatewayv2_integration" "list_layout_version" {
  api_id                 = aws_apigatewayv2_api.this.id
  integration_type       = "AWS_PROXY"
  integration_uri        = var.list_layout_version_invoke_arn
  integration_method     = "POST" # Lambda proxy integrations always invoke via POST, regardless of the route's own method
  payload_format_version = "2.0"
}

resource "aws_apigatewayv2_route" "list_layout_version" {
  api_id             = aws_apigatewayv2_api.this.id
  route_key          = "GET /locations/{locationId}/layout/versions"
  target             = "integrations/${aws_apigatewayv2_integration.list_layout_version.id}"
  authorization_type = "JWT"
  authorizer_id      = aws_apigatewayv2_authorizer.cognito.id
}

resource "aws_lambda_permission" "list_layout_version_invoke" {
  statement_id  = "AllowAPIGatewayInvoke"
  action        = "lambda:InvokeFunction"
  function_name = var.list_layout_version_function_name
  principal     = "apigateway.amazonaws.com"
  source_arn    = "${aws_apigatewayv2_api.this.execution_arn}/*/*"
}

# --- archive-layout-version (DELETE) ---
#
# Soft-archive a specific layout version. Reuses the list-layout-version Lambda
# (same ECR image, same integration) — the Lambda branches on routeKey
# "DELETE /locations/{locationId}/layout/versions/{versionId}" to perform the
# archive write instead of a list read.
#
# The lambda_permission here is intentionally route-scoped (not the wildcard
# "/*/*" used by the GET list permission above) — this route carries a write
# operation and least-privilege applies at the permission boundary too.

resource "aws_apigatewayv2_route" "archive_layout_version" {
  api_id             = aws_apigatewayv2_api.this.id
  route_key          = "DELETE /locations/{locationId}/layout/versions/{versionId}"
  target             = "integrations/${aws_apigatewayv2_integration.list_layout_version.id}"
  authorization_type = "JWT"
  authorizer_id      = aws_apigatewayv2_authorizer.cognito.id
}

resource "aws_lambda_permission" "archive_layout_version_invoke" {
  statement_id  = "AllowAPIGatewayInvokeArchiveLayoutVersion"
  action        = "lambda:InvokeFunction"
  function_name = var.list_layout_version_function_name
  principal     = "apigateway.amazonaws.com"
  source_arn    = "${aws_apigatewayv2_api.this.execution_arn}/*/DELETE/locations/*/layout/versions/*"
}

# --- list-layout-version: active layout (public) ---
#
# Public route — customer-facing site (no auth required). Reuses the
# list_layout_version integration and Lambda so no new function, integration,
# or IAM change is needed: the existing lambda_permission's source_arn
# ("${execution_arn}/*/*") already covers this route. The Lambda branches on
# the routeKey it receives to return only the floor-plan element fields
# (walls, tables, doors, windows) — version numbers, isCurrent, expiresAt,
# and audit fields are stripped before the response is sent.
#
# Note: floor area and the cash register are not stored in this table at all
# (they live only in the admin's browser); they will never appear in the
# response regardless of what fields are requested.

resource "aws_apigatewayv2_route" "get_active_layout" {
  api_id             = aws_apigatewayv2_api.this.id
  route_key          = "GET /locations/{locationId}/layout/active"
  target             = "integrations/${aws_apigatewayv2_integration.list_layout_version.id}"
  authorization_type = "NONE"
}


# --- activate-layout-version ---

resource "aws_apigatewayv2_integration" "activate_layout_version" {
  api_id                 = aws_apigatewayv2_api.this.id
  integration_type       = "AWS_PROXY"
  integration_uri        = var.activate_layout_version_invoke_arn
  integration_method     = "POST" # Lambda proxy integrations always invoke via POST, regardless of the route's own method
  payload_format_version = "2.0"
}

resource "aws_apigatewayv2_route" "activate_layout_version" {
  api_id             = aws_apigatewayv2_api.this.id
  route_key          = "POST /locations/{locationId}/layout/versions/{versionId}/activate"
  target             = "integrations/${aws_apigatewayv2_integration.activate_layout_version.id}"
  authorization_type = "JWT"
  authorizer_id      = aws_apigatewayv2_authorizer.cognito.id
}

resource "aws_lambda_permission" "activate_layout_version_invoke" {
  statement_id  = "AllowAPIGatewayInvoke"
  action        = "lambda:InvokeFunction"
  function_name = var.activate_layout_version_function_name
  principal     = "apigateway.amazonaws.com"
  source_arn    = "${aws_apigatewayv2_api.this.execution_arn}/*/*"
}


# --- pending-activation (PUT + DELETE) ---
# Both routes reuse the activate-layout-version integration and Lambda.
# No new integration or Lambda permission needed — the existing
# activate_layout_version_invoke permission covers all methods via /*/*.

resource "aws_apigatewayv2_route" "put_pending_activation" {
  api_id             = aws_apigatewayv2_api.this.id
  route_key          = "PUT /locations/{locationId}/layout/pending-activation"
  target             = "integrations/${aws_apigatewayv2_integration.activate_layout_version.id}"
  authorization_type = "JWT"
  authorizer_id      = aws_apigatewayv2_authorizer.cognito.id
}

resource "aws_apigatewayv2_route" "delete_pending_activation" {
  api_id             = aws_apigatewayv2_api.this.id
  route_key          = "DELETE /locations/{locationId}/layout/pending-activation"
  target             = "integrations/${aws_apigatewayv2_integration.activate_layout_version.id}"
  authorization_type = "JWT"
  authorizer_id      = aws_apigatewayv2_authorizer.cognito.id
}


# --- manage-auth ---

resource "aws_apigatewayv2_integration" "manage_auth" {
  api_id                 = aws_apigatewayv2_api.this.id
  integration_type       = "AWS_PROXY"
  integration_uri        = var.manage_auth_invoke_arn
  integration_method     = "POST" # Lambda proxy integrations always invoke via POST, regardless of the route's own method
  payload_format_version = "2.0"
}

# Auth here is already NONE, so this route was never the source of the
# 401-on-preflight bug - but ANY still means an OPTIONS preflight gets
# proxied straight to the Lambda instead of getting the automatic,
# integration-free 204 API Gateway would otherwise answer with. That's
# fragile (every deploy of manage-auth has to also special-case OPTIONS
# and return a clean 2xx, or preflight breaks) and adds an unnecessary
# invocation on every preflight. Per LAMBDA_REFERENCE.md ("sign-in,
# MFA/challenge responses, token refresh") this is a POST-only API - no
# GET sub-paths expected.
locals {
  manage_auth_methods = ["POST"]
}

resource "aws_apigatewayv2_route" "manage_auth" {
  for_each = toset(local.manage_auth_methods)

  api_id             = aws_apigatewayv2_api.this.id
  route_key          = "${each.value} /auth/{proxy+}"
  target             = "integrations/${aws_apigatewayv2_integration.manage_auth.id}"
  authorization_type = "NONE"
}

resource "aws_lambda_permission" "manage_auth_invoke" {
  statement_id  = "AllowAPIGatewayInvoke"
  action        = "lambda:InvokeFunction"
  function_name = var.manage_auth_function_name
  principal     = "apigateway.amazonaws.com"
  source_arn    = "${aws_apigatewayv2_api.this.execution_arn}/*/*"
}


# --- manage-user ---

resource "aws_apigatewayv2_integration" "manage_user" {
  api_id                 = aws_apigatewayv2_api.this.id
  integration_type       = "AWS_PROXY"
  integration_uri        = var.manage_user_invoke_arn
  integration_method     = "POST" # Lambda proxy integrations always invoke via POST, regardless of the route's own method
  payload_format_version = "2.0"
}


# NOTE: previously a single "ANY /users/{proxy+}" route. ANY matches every
# HTTP method literally, including OPTIONS - so the browser's CORS
# preflight for e.g. POST /users/invite was being routed here and
# rejected by the JWT authorizer (preflight requests never carry
# Authorization), breaking every cross-origin call to this resource.
# HTTP APIs handle preflight automatically via the api-level
# cors_configuration block above, but only for paths with no explicit
# route match - explicit method routes below (none of them OPTIONS)
# let that automatic, unauthenticated 204 response take over again for
# OPTIONS, while GET/POST/PUT/DELETE stay behind the JWT authorizer
# exactly as before. The for_each below already handles any further
# method manage-user grows - just add it to the list.
locals {
  manage_user_methods = ["GET", "POST", "PUT", "DELETE"]
}

resource "aws_apigatewayv2_route" "manage_user" {
  for_each = toset(local.manage_user_methods)

  api_id             = aws_apigatewayv2_api.this.id
  route_key          = "${each.value} /users/{proxy+}"
  target             = "integrations/${aws_apigatewayv2_integration.manage_user.id}"
  authorization_type = "JWT"
  authorizer_id      = aws_apigatewayv2_authorizer.cognito.id
}

resource "aws_lambda_permission" "manage_user_invoke" {
  statement_id  = "AllowAPIGatewayInvoke"
  action        = "lambda:InvokeFunction"
  function_name = var.manage_user_function_name
  principal     = "apigateway.amazonaws.com"
  source_arn    = "${aws_apigatewayv2_api.this.execution_arn}/*/*"
}

# --- list-users ---
#
# Reuses the manage-user integration/Lambda above instead of a separate
# function - GET /users/{proxy+} already covers "fetch/list staff
# profiles" per that Lambda's own purpose, so this is an additional path
# to the same handler, not new logic. No new aws_lambda_permission needed:
# manage_user_invoke's source_arn ("${execution_arn}/*/*") already covers
# this route too.

resource "aws_apigatewayv2_route" "list_users" {
  api_id             = aws_apigatewayv2_api.this.id
  route_key          = "GET /list-users"
  target             = "integrations/${aws_apigatewayv2_integration.manage_user.id}"
  authorization_type = "JWT"
  authorizer_id      = aws_apigatewayv2_authorizer.cognito.id
}


# --- pre-signed-url ---

resource "aws_apigatewayv2_integration" "pre_signed_url" {
  api_id                 = aws_apigatewayv2_api.this.id
  integration_type       = "AWS_PROXY"
  integration_uri        = var.pre_signed_url_invoke_arn
  integration_method     = "POST" # Lambda proxy integrations always invoke via POST, regardless of the route's own method
  payload_format_version = "2.0"
}

resource "aws_apigatewayv2_route" "pre_signed_url" {
  api_id             = aws_apigatewayv2_api.this.id
  route_key          = "GET /menu-images/presigned-url"
  target             = "integrations/${aws_apigatewayv2_integration.pre_signed_url.id}"
  authorization_type = "JWT"
  authorizer_id      = aws_apigatewayv2_authorizer.cognito.id
}

resource "aws_lambda_permission" "pre_signed_url_invoke" {
  statement_id  = "AllowAPIGatewayInvoke"
  action        = "lambda:InvokeFunction"
  function_name = var.pre_signed_url_function_name
  principal     = "apigateway.amazonaws.com"
  source_arn    = "${aws_apigatewayv2_api.this.execution_arn}/*/*"
}


# --- manage-order ---
#
# Staff/owner order management (own tenant): the day's-orders dashboard
# Query (GET on the collection), kitchen status updates (PUT), staff-
# created orders (POST), and cancellations (DELETE). All JWT-protected -
# customers never call this; their reads go through get-order and their
# orders are created by the checkout flow. Reads live here (not in a
# public lambda) because a location's order list is operational data.

resource "aws_apigatewayv2_integration" "manage_order" {
  api_id                 = aws_apigatewayv2_api.this.id
  integration_type       = "AWS_PROXY"
  integration_uri        = var.manage_order_invoke_arn
  integration_method     = "POST" # Lambda proxy integrations always invoke via POST, regardless of the route's own method
  payload_format_version = "2.0"
}

locals {
  manage_order_methods = ["GET", "POST", "PUT", "DELETE"]
}

# Collection route: GET /locations/{locationId}/orders?date=YYYY-MM-DD is
# the one-Query dashboard read; POST creates a staff-entered order.
resource "aws_apigatewayv2_route" "manage_order_collection" {
  for_each = toset(local.manage_order_methods)

  api_id             = aws_apigatewayv2_api.this.id
  route_key          = "${each.value} /locations/{locationId}/orders"
  target             = "integrations/${aws_apigatewayv2_integration.manage_order.id}"
  authorization_type = "JWT"
  authorizer_id      = aws_apigatewayv2_authorizer.cognito.id
}

# Item routes: status updates / cancellation of one order by its key.
resource "aws_apigatewayv2_route" "manage_order" {
  for_each = toset(local.manage_order_methods)

  api_id             = aws_apigatewayv2_api.this.id
  route_key          = "${each.value} /locations/{locationId}/orders/{proxy+}"
  target             = "integrations/${aws_apigatewayv2_integration.manage_order.id}"
  authorization_type = "JWT"
  authorizer_id      = aws_apigatewayv2_authorizer.cognito.id
}

resource "aws_lambda_permission" "manage_order_invoke" {
  statement_id  = "AllowAPIGatewayInvoke"
  action        = "lambda:InvokeFunction"
  function_name = var.manage_order_function_name
  principal     = "apigateway.amazonaws.com"
  source_arn    = "${aws_apigatewayv2_api.this.execution_arn}/*/*"
}


# ── catering-settings ─────────────────────────────────────────────────────────
#
# Manages the cateringSettings map attribute embedded on the location item.
# GET is unauthenticated — customers need the settings to render the calculator
# (delivery window, minimum notice, etc.) without signing in.
# PUT is JWT-protected — only owners and staff can change these settings.

resource "aws_apigatewayv2_integration" "catering_settings" {
  api_id                 = aws_apigatewayv2_api.this.id
  integration_type       = "AWS_PROXY"
  integration_uri        = var.catering_settings_invoke_arn
  integration_method     = "POST" # Lambda proxy integrations always invoke via POST, regardless of the route's own method
  payload_format_version = "2.0"
}

# --- catering-settings ---
resource "aws_apigatewayv2_route" "catering_settings_get" {
  api_id             = aws_apigatewayv2_api.this.id
  route_key          = "GET /locations/{locationId}/catering/settings"
  target             = "integrations/${aws_apigatewayv2_integration.catering_settings.id}"
  authorization_type = "NONE"
}

# --- catering-settings ---
resource "aws_apigatewayv2_route" "catering_settings_put" {
  api_id             = aws_apigatewayv2_api.this.id
  route_key          = "PUT /locations/{locationId}/catering/settings"
  target             = "integrations/${aws_apigatewayv2_integration.catering_settings.id}"
  authorization_type = "JWT"
  authorizer_id      = aws_apigatewayv2_authorizer.cognito.id
}

resource "aws_lambda_permission" "catering_settings_invoke" {
  statement_id  = "AllowAPIGatewayInvokeCateringSettings"
  action        = "lambda:InvokeFunction"
  function_name = var.catering_settings_function_name
  principal     = "apigateway.amazonaws.com"
  source_arn    = "${aws_apigatewayv2_api.this.execution_arn}/*/*"
}


# ── catering-discount-tiers ───────────────────────────────────────────────────
#
# Volume-based discount tiers per location. GET is unauthenticated so customers
# can see the tiers in the calculator before submitting a request. POST, PUT and
# DELETE are JWT-protected — only owners and staff manage the tier schedule.

resource "aws_apigatewayv2_integration" "catering_discount_tiers" {
  api_id                 = aws_apigatewayv2_api.this.id
  integration_type       = "AWS_PROXY"
  integration_uri        = var.catering_discount_tiers_invoke_arn
  integration_method     = "POST" # Lambda proxy integrations always invoke via POST, regardless of the route's own method
  payload_format_version = "2.0"
}

# --- catering-discount-tiers ---
resource "aws_apigatewayv2_route" "catering_discount_tiers_get" {
  api_id             = aws_apigatewayv2_api.this.id
  route_key          = "GET /locations/{locationId}/catering/discount-tiers"
  target             = "integrations/${aws_apigatewayv2_integration.catering_discount_tiers.id}"
  authorization_type = "NONE"
}

# --- catering-discount-tiers ---
resource "aws_apigatewayv2_route" "catering_discount_tiers_post" {
  api_id             = aws_apigatewayv2_api.this.id
  route_key          = "POST /locations/{locationId}/catering/discount-tiers"
  target             = "integrations/${aws_apigatewayv2_integration.catering_discount_tiers.id}"
  authorization_type = "JWT"
  authorizer_id      = aws_apigatewayv2_authorizer.cognito.id
}

# --- catering-discount-tiers ---
resource "aws_apigatewayv2_route" "catering_discount_tiers_put" {
  api_id             = aws_apigatewayv2_api.this.id
  route_key          = "PUT /locations/{locationId}/catering/discount-tiers/{tierId}"
  target             = "integrations/${aws_apigatewayv2_integration.catering_discount_tiers.id}"
  authorization_type = "JWT"
  authorizer_id      = aws_apigatewayv2_authorizer.cognito.id
}

# --- catering-discount-tiers ---
resource "aws_apigatewayv2_route" "catering_discount_tiers_delete" {
  api_id             = aws_apigatewayv2_api.this.id
  route_key          = "DELETE /locations/{locationId}/catering/discount-tiers/{tierId}"
  target             = "integrations/${aws_apigatewayv2_integration.catering_discount_tiers.id}"
  authorization_type = "JWT"
  authorizer_id      = aws_apigatewayv2_authorizer.cognito.id
}

resource "aws_lambda_permission" "catering_discount_tiers_invoke" {
  statement_id  = "AllowAPIGatewayInvokeCateringDiscountTiers"
  action        = "lambda:InvokeFunction"
  function_name = var.catering_discount_tiers_function_name
  principal     = "apigateway.amazonaws.com"
  source_arn    = "${aws_apigatewayv2_api.this.execution_arn}/*/*"
}


# ── catering-requests ─────────────────────────────────────────────────────────
#
# Customer-submitted catering enquiries and owner responses.
# POST is unauthenticated — customers submit requests without an account.
# GET is JWT-protected — only owners and staff can list a location's requests.
# Everything that happens to a request afterwards (adjust, send, decline,
# cancel, delivered) goes through catering-offer below; the former
# PATCH accept/reject route was removed with the offer workflow.

resource "aws_apigatewayv2_integration" "catering_requests" {
  api_id                 = aws_apigatewayv2_api.this.id
  integration_type       = "AWS_PROXY"
  integration_uri        = var.catering_requests_invoke_arn
  integration_method     = "POST" # Lambda proxy integrations always invoke via POST, regardless of the route's own method
  payload_format_version = "2.0"
}

# --- catering-requests ---
resource "aws_apigatewayv2_route" "catering_requests_post" {
  api_id             = aws_apigatewayv2_api.this.id
  route_key          = "POST /locations/{locationId}/catering/requests"
  target             = "integrations/${aws_apigatewayv2_integration.catering_requests.id}"
  authorization_type = "NONE"
}

# --- catering-requests ---
resource "aws_apigatewayv2_route" "catering_requests_get" {
  api_id             = aws_apigatewayv2_api.this.id
  route_key          = "GET /locations/{locationId}/catering/requests"
  target             = "integrations/${aws_apigatewayv2_integration.catering_requests.id}"
  authorization_type = "JWT"
  authorizer_id      = aws_apigatewayv2_authorizer.cognito.id
}

resource "aws_lambda_permission" "catering_requests_invoke" {
  statement_id  = "AllowAPIGatewayInvokeCateringRequests"
  action        = "lambda:InvokeFunction"
  function_name = var.catering_requests_function_name
  principal     = "apigateway.amazonaws.com"
  source_arn    = "${aws_apigatewayv2_api.this.execution_arn}/*/*"
}


# --- catering-offer ---
#
# Owner side of the catering workflow. Every route is JWT-protected; the
# handler additionally checks that the caller's Cognito user belongs to
# {locationId} (the authorizer only proves the token is valid).

resource "aws_apigatewayv2_integration" "catering_offer" {
  api_id                 = aws_apigatewayv2_api.this.id
  integration_type       = "AWS_PROXY"
  integration_uri        = var.catering_offer_invoke_arn
  integration_method     = "POST" # Lambda proxy integrations always invoke via POST, regardless of the route's own method
  payload_format_version = "2.0"
}

# Request detail for the owner: head item, every offer version and the audit log.

resource "aws_apigatewayv2_route" "catering_offer_get" {
  api_id             = aws_apigatewayv2_api.this.id
  route_key          = "GET /locations/{locationId}/catering/requests/{requestId}"
  target             = "integrations/${aws_apigatewayv2_integration.catering_offer.id}"
  authorization_type = "JWT"
  authorizer_id      = aws_apigatewayv2_authorizer.cognito.id
}

# --- catering-offer ---
# Presigned download URL for an offer, signed agreement or invoice PDF.

resource "aws_apigatewayv2_route" "catering_offer_documents_get" {
  api_id             = aws_apigatewayv2_api.this.id
  route_key          = "GET /locations/{locationId}/catering/requests/{requestId}/documents/{docId}"
  target             = "integrations/${aws_apigatewayv2_integration.catering_offer.id}"
  authorization_type = "JWT"
  authorizer_id      = aws_apigatewayv2_authorizer.cognito.id
}

# --- catering-offer ---
# Save an adjusted draft - every save is a new, immutable offer version.

resource "aws_apigatewayv2_route" "catering_offer_offer_put" {
  api_id             = aws_apigatewayv2_api.this.id
  route_key          = "PUT /locations/{locationId}/catering/requests/{requestId}/offer"
  target             = "integrations/${aws_apigatewayv2_integration.catering_offer.id}"
  authorization_type = "JWT"
  authorizer_id      = aws_apigatewayv2_authorizer.cognito.id
}

# --- catering-offer ---
# Render the PDF, reserve the date's capacity and send version N to the customer.

resource "aws_apigatewayv2_route" "catering_offer_offer_send" {
  api_id             = aws_apigatewayv2_api.this.id
  route_key          = "POST /locations/{locationId}/catering/requests/{requestId}/offer/send"
  target             = "integrations/${aws_apigatewayv2_integration.catering_offer.id}"
  authorization_type = "JWT"
  authorizer_id      = aws_apigatewayv2_authorizer.cognito.id
}

# --- catering-offer ---
# Decline with a reason - releases any held capacity.

resource "aws_apigatewayv2_route" "catering_offer_decline" {
  api_id             = aws_apigatewayv2_api.this.id
  route_key          = "POST /locations/{locationId}/catering/requests/{requestId}/decline"
  target             = "integrations/${aws_apigatewayv2_integration.catering_offer.id}"
  authorization_type = "JWT"
  authorizer_id      = aws_apigatewayv2_authorizer.cognito.id
}

# --- catering-offer ---
# Restaurant-only cancellation of a confirmed order - Stripe refund (private) or credit note (company).

resource "aws_apigatewayv2_route" "catering_offer_cancel" {
  api_id             = aws_apigatewayv2_api.this.id
  route_key          = "POST /locations/{locationId}/catering/requests/{requestId}/cancel"
  target             = "integrations/${aws_apigatewayv2_integration.catering_offer.id}"
  authorization_type = "JWT"
  authorizer_id      = aws_apigatewayv2_authorizer.cognito.id
}

# --- catering-offer ---
# Mark delivered/picked up - the order closes once it's also paid.

resource "aws_apigatewayv2_route" "catering_offer_delivered" {
  api_id             = aws_apigatewayv2_api.this.id
  route_key          = "POST /locations/{locationId}/catering/requests/{requestId}/delivered"
  target             = "integrations/${aws_apigatewayv2_integration.catering_offer.id}"
  authorization_type = "JWT"
  authorizer_id      = aws_apigatewayv2_authorizer.cognito.id
}

# --- catering-offer ---
# Invoice register for the dashboard (mirrored from Stripe).

resource "aws_apigatewayv2_route" "catering_offer_invoices_get" {
  api_id             = aws_apigatewayv2_api.this.id
  route_key          = "GET /locations/{locationId}/catering/invoices"
  target             = "integrations/${aws_apigatewayv2_integration.catering_offer.id}"
  authorization_type = "JWT"
  authorizer_id      = aws_apigatewayv2_authorizer.cognito.id
}

# --- catering-offer ---
# Record a Bankgiro payment - marks the Stripe invoice paid out of band.

resource "aws_apigatewayv2_route" "catering_offer_invoice_mark_paid" {
  api_id             = aws_apigatewayv2_api.this.id
  route_key          = "POST /locations/{locationId}/catering/invoices/{invoiceId}/mark-paid"
  target             = "integrations/${aws_apigatewayv2_integration.catering_offer.id}"
  authorization_type = "JWT"
  authorizer_id      = aws_apigatewayv2_authorizer.cognito.id
}

resource "aws_lambda_permission" "catering_offer_invoke" {
  statement_id  = "AllowAPIGatewayInvoke"
  action        = "lambda:InvokeFunction"
  function_name = var.catering_offer_function_name
  principal     = "apigateway.amazonaws.com"
  source_arn    = "${aws_apigatewayv2_api.this.execution_arn}/*/*"
}


# --- catering-customer ---
#
# Customer side of the catering workflow, reached through the magic link -
# no account, so NONE at the gateway. The authentication boundary is the
# handler's check of the HMAC sent in the x-order-token header (see
# security/secrets/catering), scoped to exactly this location + request.

resource "aws_apigatewayv2_integration" "catering_customer" {
  api_id                 = aws_apigatewayv2_api.this.id
  integration_type       = "AWS_PROXY"
  integration_uri        = var.catering_customer_invoke_arn
  integration_method     = "POST" # Lambda proxy integrations always invoke via POST, regardless of the route's own method
  payload_format_version = "2.0"
}

# The customer's view of their request/offer.

resource "aws_apigatewayv2_route" "catering_customer_get" {
  api_id             = aws_apigatewayv2_api.this.id
  route_key          = "GET /locations/{locationId}/catering/requests/{requestId}/customer"
  target             = "integrations/${aws_apigatewayv2_integration.catering_customer.id}"
  authorization_type = "NONE"
}

# --- catering-customer ---
# Start BankID signing of the current offer version (terms must be accepted).

resource "aws_apigatewayv2_route" "catering_customer_sign" {
  api_id             = aws_apigatewayv2_api.this.id
  route_key          = "POST /locations/{locationId}/catering/requests/{requestId}/customer/sign"
  target             = "integrations/${aws_apigatewayv2_integration.catering_customer.id}"
  authorization_type = "NONE"
}

# --- catering-customer ---
# Private customers: start (or retry) Stripe Checkout after signing.

resource "aws_apigatewayv2_route" "catering_customer_checkout" {
  api_id             = aws_apigatewayv2_api.this.id
  route_key          = "POST /locations/{locationId}/catering/requests/{requestId}/customer/checkout"
  target             = "integrations/${aws_apigatewayv2_integration.catering_customer.id}"
  authorization_type = "NONE"
}

# --- catering-customer ---
# Presigned download URL for the customer's own offer or signed agreement.

resource "aws_apigatewayv2_route" "catering_customer_documents_get" {
  api_id             = aws_apigatewayv2_api.this.id
  route_key          = "GET /locations/{locationId}/catering/requests/{requestId}/customer/documents/{docId}"
  target             = "integrations/${aws_apigatewayv2_integration.catering_customer.id}"
  authorization_type = "NONE"
}

resource "aws_lambda_permission" "catering_customer_invoke" {
  statement_id  = "AllowAPIGatewayInvoke"
  action        = "lambda:InvokeFunction"
  function_name = var.catering_customer_function_name
  principal     = "apigateway.amazonaws.com"
  source_arn    = "${aws_apigatewayv2_api.this.execution_arn}/*/*"
}


# --- catering-signing-webhook ---
#
# BankID signing provider callbacks. Unauthenticated at the gateway - the
# real authentication boundary is the handler's verification of the
# provider's callback signature with the webhookSecret in the
# signing-provider secret. Register this URL with the provider (output
# catering_signing_webhook_url) - or the handler passes it per signing order.

resource "aws_apigatewayv2_integration" "catering_signing_webhook" {
  api_id                 = aws_apigatewayv2_api.this.id
  integration_type       = "AWS_PROXY"
  integration_uri        = var.catering_signing_webhook_invoke_arn
  integration_method     = "POST" # Lambda proxy integrations always invoke via POST, regardless of the route's own method
  payload_format_version = "2.0"
}

resource "aws_apigatewayv2_route" "catering_signing_webhook_post" {
  api_id             = aws_apigatewayv2_api.this.id
  route_key          = "POST /webhooks/signing/catering"
  target             = "integrations/${aws_apigatewayv2_integration.catering_signing_webhook.id}"
  authorization_type = "NONE"
}

resource "aws_lambda_permission" "catering_signing_webhook_invoke" {
  statement_id  = "AllowAPIGatewayInvoke"
  action        = "lambda:InvokeFunction"
  function_name = var.catering_signing_webhook_function_name
  principal     = "apigateway.amazonaws.com"
  source_arn    = "${aws_apigatewayv2_api.this.execution_arn}/*/*"
}


# --- platform-tenants ---
#
# The operator dashboard's API: tenants, plans, domains, suspension,
# offboarding. Operator pool token + platform/admin scope, checked by API
# Gateway. Provisioning itself runs in Step Functions
# (orchestration/tenant-workflows) - this Lambda validates, writes the
# tenant row and starts the workflow.

locals {
  platform_tenants_routes = [
    "GET /platform/plans",
    "GET /platform/tenants",
    "POST /platform/tenants",
    "GET /platform/tenants/{tenantId}",
    "PATCH /platform/tenants/{tenantId}",
    "PUT /platform/tenants/{tenantId}/plan",
    "POST /platform/tenants/{tenantId}/suspend",
    "POST /platform/tenants/{tenantId}/resume",
    "POST /platform/tenants/{tenantId}/offboard",
    "POST /platform/tenants/{tenantId}/onboarding/retry",
    "GET /platform/tenants/{tenantId}/users",
    "POST /platform/tenants/{tenantId}/owners",
    "GET /platform/tenants/{tenantId}/locations",
    "POST /platform/tenants/{tenantId}/locations",
    "PATCH /platform/tenants/{tenantId}/locations/{locationId}",
    "DELETE /platform/tenants/{tenantId}/locations/{locationId}",
    "POST /platform/tenants/{tenantId}/domains",
    "DELETE /platform/tenants/{tenantId}/domains/{domain}",
    "POST /platform/tenants/{tenantId}/stripe/account-link",
    "POST /platform/tenants/{tenantId}/stripe/sync",
  ]
}

resource "aws_apigatewayv2_integration" "platform_tenants" {
  api_id                 = aws_apigatewayv2_api.this.id
  integration_type       = "AWS_PROXY"
  integration_uri        = var.platform_tenants_invoke_arn
  integration_method     = "POST" # Lambda proxy integrations always invoke via POST, regardless of the route's own method
  payload_format_version = "2.0"
}

resource "aws_apigatewayv2_route" "platform_tenants" {
  for_each = toset(local.platform_tenants_routes)

  api_id               = aws_apigatewayv2_api.this.id
  route_key            = each.value
  target               = "integrations/${aws_apigatewayv2_integration.platform_tenants.id}"
  authorization_type   = "JWT"
  authorizer_id        = aws_apigatewayv2_authorizer.platform.id
  authorization_scopes = [var.platform_admin_scope]
}

resource "aws_lambda_permission" "platform_tenants_invoke" {
  statement_id  = "AllowAPIGatewayInvoke"
  action        = "lambda:InvokeFunction"
  function_name = var.platform_tenants_function_name
  principal     = "apigateway.amazonaws.com"
  source_arn    = "${aws_apigatewayv2_api.this.execution_arn}/*/*"
}


# --- tenant-account ---
#
# An owner's own tenant: plan, usage, domains, Stripe onboarding status;
# edit sender name/reply-to/branding; fresh Stripe onboarding link. Tenant
# pool token - the handler reads tenant_id from the token, never from the
# request, and requires role owner_user for anything but GET.

locals {
  tenant_account_routes = [
    "GET /tenant",
    "PATCH /tenant",
    "POST /tenant/stripe/account-link",
  ]
}

resource "aws_apigatewayv2_integration" "tenant_account" {
  api_id                 = aws_apigatewayv2_api.this.id
  integration_type       = "AWS_PROXY"
  integration_uri        = var.tenant_account_invoke_arn
  integration_method     = "POST" # Lambda proxy integrations always invoke via POST, regardless of the route's own method
  payload_format_version = "2.0"
}

resource "aws_apigatewayv2_route" "tenant_account" {
  for_each = toset(local.tenant_account_routes)

  api_id             = aws_apigatewayv2_api.this.id
  route_key          = each.value
  target             = "integrations/${aws_apigatewayv2_integration.tenant_account.id}"
  authorization_type = "JWT"
  authorizer_id      = aws_apigatewayv2_authorizer.cognito.id
}

resource "aws_lambda_permission" "tenant_account_invoke" {
  statement_id  = "AllowAPIGatewayInvoke"
  action        = "lambda:InvokeFunction"
  function_name = var.tenant_account_function_name
  principal     = "apigateway.amazonaws.com"
  source_arn    = "${aws_apigatewayv2_api.this.execution_arn}/*/*"
}


# --- tenant-site-config ---
#
# Public bootstrap call every tenant website makes on load:
# GET /site-config?host=<window.location.hostname> -> which tenant this site
# is, its locations, branding, enabled features. The site template is the
# same for every tenant; only the hostname differs.

resource "aws_apigatewayv2_integration" "tenant_site_config" {
  api_id                 = aws_apigatewayv2_api.this.id
  integration_type       = "AWS_PROXY"
  integration_uri        = var.tenant_site_config_invoke_arn
  integration_method     = "POST" # Lambda proxy integrations always invoke via POST, regardless of the route's own method
  payload_format_version = "2.0"
}

resource "aws_apigatewayv2_route" "tenant_site_config" {
  api_id             = aws_apigatewayv2_api.this.id
  route_key          = "GET /site-config"
  target             = "integrations/${aws_apigatewayv2_integration.tenant_site_config.id}"
  authorization_type = "NONE"
}

resource "aws_lambda_permission" "tenant_site_config_invoke" {
  statement_id  = "AllowAPIGatewayInvoke"
  action        = "lambda:InvokeFunction"
  function_name = var.tenant_site_config_function_name
  principal     = "apigateway.amazonaws.com"
  source_arn    = "${aws_apigatewayv2_api.this.execution_arn}/*/*"
}
