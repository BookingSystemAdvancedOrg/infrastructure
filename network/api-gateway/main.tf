locals {
  api_name = var.environment == "prod" ? "bsa-api" : "${var.environment}-bsa-api"
}

resource "aws_apigatewayv2_api" "this" {
  name          = local.api_name
  protocol_type = "HTTP"

  # Authorization header is what carries the Cognito JWT - it has to be an
  # allowed header or the browser's preflight OPTIONS request fails before
  # the real request is ever sent. Wildcard origin is not used on purpose:
  # a wildcard origin can't be combined with credentialed requests anyway,
  # and this repo already treats "allow everything" as something to avoid
  # by default (same reasoning as scoping IAM to specific actions/tables
  # elsewhere) - allowed_origins is a real list of front-end origins.
  cors_configuration {
    allow_origins = var.allowed_origins
    allow_methods = ["GET", "POST", "PUT", "DELETE", "OPTIONS"]
    allow_headers = ["authorization", "content-type"]
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


# --- get-menu ---

resource "aws_apigatewayv2_integration" "get_menu" {
  api_id                 = aws_apigatewayv2_api.this.id
  integration_type       = "AWS_PROXY"
  integration_uri        = var.get_menu_invoke_arn
  integration_method     = "POST" # Lambda proxy integrations always invoke via POST, regardless of the route's own method
  payload_format_version = "2.0"
}

resource "aws_apigatewayv2_route" "get_menu" {
  api_id             = aws_apigatewayv2_api.this.id
  route_key          = "GET /locations/{locationId}/menu"
  target             = "integrations/${aws_apigatewayv2_integration.get_menu.id}"
  authorization_type = "NONE"
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

resource "aws_apigatewayv2_route" "manage_menu" {
  api_id             = aws_apigatewayv2_api.this.id
  route_key          = "ANY /locations/{locationId}/menu/{proxy+}"
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

resource "aws_apigatewayv2_route" "manage_layout_element" {
  api_id             = aws_apigatewayv2_api.this.id
  route_key          = "ANY /locations/{locationId}/layout-elements/{proxy+}"
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


# --- manage-auth ---

resource "aws_apigatewayv2_integration" "manage_auth" {
  api_id                 = aws_apigatewayv2_api.this.id
  integration_type       = "AWS_PROXY"
  integration_uri        = var.manage_auth_invoke_arn
  integration_method     = "POST" # Lambda proxy integrations always invoke via POST, regardless of the route's own method
  payload_format_version = "2.0"
}

resource "aws_apigatewayv2_route" "manage_auth" {
  api_id             = aws_apigatewayv2_api.this.id
  route_key          = "ANY /auth/{proxy+}"
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

resource "aws_apigatewayv2_route" "manage_user" {
  api_id             = aws_apigatewayv2_api.this.id
  route_key          = "ANY /users/{proxy+}"
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
