# Kassa, the till (feature "kassa"), kassa function (tenant pool JWT; owner
# or staff, owner-only actions are checked in the handler):
#   GET          /locations/{locationId}/kassa          registers, open bills, test mode
#   GET|POST|PUT /locations/{locationId}/kassa/{proxy+} registers, bills, payments, receipts,
#                returns, copies, X/Z reports, journal export
# Card payment polling, cancel and retry stay on terminal-payments.

resource "aws_apigatewayv2_integration" "kassa" {
  api_id                 = aws_apigatewayv2_api.this.id
  integration_type       = "AWS_PROXY"
  integration_uri        = var.kassa_invoke_arn
  integration_method     = "POST" # Lambda proxy integrations always invoke via POST, regardless of the route's own method
  payload_format_version = "2.0"
}

resource "aws_lambda_permission" "kassa_invoke" {
  statement_id  = "AllowAPIGatewayInvoke"
  action        = "lambda:InvokeFunction"
  function_name = var.kassa_function_name
  qualifier     = var.lambda_alias_name
  principal     = "apigateway.amazonaws.com"
  source_arn    = "${aws_apigatewayv2_api.this.execution_arn}/*/*"
}

# --- kassa ---
locals {
  kassa_routes = ["GET /locations/{locationId}/kassa", "GET /locations/{locationId}/kassa/{proxy+}",
  "POST /locations/{locationId}/kassa/{proxy+}", "PUT /locations/{locationId}/kassa/{proxy+}"]
}

resource "aws_apigatewayv2_route" "kassa" {
  for_each = toset(local.kassa_routes)

  api_id             = aws_apigatewayv2_api.this.id
  route_key          = each.value
  target             = "integrations/${aws_apigatewayv2_integration.kassa.id}"
  authorization_type = "JWT"
  authorizer_id      = aws_apigatewayv2_authorizer.cognito.id
}
