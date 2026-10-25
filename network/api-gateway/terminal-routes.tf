# Card payments at the till (backlog 23), terminal-payments (tenant pool
# JWT; owner or staff, the refund is owner-only in the handler):
#   GET|POST /locations/{locationId}/card-payments          the day's payments, take a payment
#   GET|POST /locations/{locationId}/card-payments/{proxy+} readers, one payment (poll),
#            cancel, retry, refund, receipt, simulate (test mode)
# Stripe's reader events reach the same function through its Function URL
# (terminal module), not API Gateway.

resource "aws_apigatewayv2_integration" "terminal_payments" {
  api_id                 = aws_apigatewayv2_api.this.id
  integration_type       = "AWS_PROXY"
  integration_uri        = var.terminal_payments_invoke_arn
  integration_method     = "POST" # Lambda proxy integrations always invoke via POST, regardless of the route's own method
  payload_format_version = "2.0"
}

resource "aws_lambda_permission" "terminal_payments_invoke" {
  statement_id  = "AllowAPIGatewayInvoke"
  action        = "lambda:InvokeFunction"
  function_name = var.terminal_payments_function_name
  qualifier     = var.lambda_alias_name
  principal     = "apigateway.amazonaws.com"
  source_arn    = "${aws_apigatewayv2_api.this.execution_arn}/*/*"
}

# --- terminal-payments ---
locals {
  terminal_payments_routes = ["GET /locations/{locationId}/card-payments", "POST /locations/{locationId}/card-payments",
  "GET /locations/{locationId}/card-payments/{proxy+}", "POST /locations/{locationId}/card-payments/{proxy+}"]
}

resource "aws_apigatewayv2_route" "terminal_payments" {
  for_each = toset(local.terminal_payments_routes)

  api_id             = aws_apigatewayv2_api.this.id
  route_key          = each.value
  target             = "integrations/${aws_apigatewayv2_integration.terminal_payments.id}"
  authorization_type = "JWT"
  authorizer_id      = aws_apigatewayv2_authorizer.cognito.id
}
