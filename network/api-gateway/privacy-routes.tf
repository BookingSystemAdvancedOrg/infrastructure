# --- guest privacy -----------------------------------------------------------
#
# guest-privacy (tenant pool JWT, owners only in the handler):
#   GET|PUT|DELETE /privacy/notice       the restaurant's privacy notice
#   GET  /privacy/consents               one guest's consent state and history
#   POST /privacy/consents/withdraw      withdraw on the guest's behalf
#
# marketing-public (no auth, HMAC-signed link that expires):
#   GET|POST /m/w/{token}                the guest's own withdrawal page
#                                        (GET shows a button, POST withdraws)

locals {
  guest_privacy_routes = [
    "GET /privacy/notice",
    "PUT /privacy/notice",
    "DELETE /privacy/notice",
    "GET /privacy/consents",
    "POST /privacy/consents/withdraw",
  ]
  consent_withdraw_routes = ["GET /m/w/{token}", "POST /m/w/{token}"]
}

resource "aws_apigatewayv2_integration" "guest_privacy" {
  api_id                 = aws_apigatewayv2_api.this.id
  integration_type       = "AWS_PROXY"
  integration_uri        = var.guest_privacy_invoke_arn
  integration_method     = "POST" # Lambda proxy integrations always invoke via POST, regardless of the route's own method
  payload_format_version = "2.0"
}

resource "aws_apigatewayv2_route" "guest_privacy" {
  for_each = toset(local.guest_privacy_routes)

  api_id             = aws_apigatewayv2_api.this.id
  route_key          = each.value
  target             = "integrations/${aws_apigatewayv2_integration.guest_privacy.id}"
  authorization_type = "JWT"
  authorizer_id      = aws_apigatewayv2_authorizer.cognito.id
}

resource "aws_lambda_permission" "guest_privacy_invoke" {
  statement_id  = "AllowAPIGatewayInvoke"
  action        = "lambda:InvokeFunction"
  function_name = var.guest_privacy_function_name
  qualifier     = var.lambda_alias_name
  principal     = "apigateway.amazonaws.com"
  source_arn    = "${aws_apigatewayv2_api.this.execution_arn}/*/*"
}

# Same integration (and invoke permission) as the other marketing-public routes.
resource "aws_apigatewayv2_route" "consent_withdraw" {
  for_each = toset(local.consent_withdraw_routes)

  api_id             = aws_apigatewayv2_api.this.id
  route_key          = each.value
  target             = "integrations/${aws_apigatewayv2_integration.marketing_public.id}"
  authorization_type = "NONE"
}
