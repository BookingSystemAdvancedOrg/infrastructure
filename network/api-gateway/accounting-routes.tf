# Accounting export (Bokföring), accounting function (tenant pool JWT; owner
# only, checked in the handler):
#   GET|PUT /locations/{locationId}/accounting          the BAS account mapping
#   GET     /locations/{locationId}/accounting/export   SIE 4 / CSV / JSON for a period

resource "aws_apigatewayv2_integration" "accounting" {
  api_id                 = aws_apigatewayv2_api.this.id
  integration_type       = "AWS_PROXY"
  integration_uri        = var.accounting_invoke_arn
  integration_method     = "POST" # Lambda proxy integrations always invoke via POST, regardless of the route's own method
  payload_format_version = "2.0"
}

resource "aws_lambda_permission" "accounting_invoke" {
  statement_id  = "AllowAPIGatewayInvoke"
  action        = "lambda:InvokeFunction"
  function_name = var.accounting_function_name
  qualifier     = var.lambda_alias_name
  principal     = "apigateway.amazonaws.com"
  source_arn    = "${aws_apigatewayv2_api.this.execution_arn}/*/*"
}

# --- accounting ---
locals {
  accounting_routes = ["GET /locations/{locationId}/accounting", "PUT /locations/{locationId}/accounting",
  "GET /locations/{locationId}/accounting/export"]
}

resource "aws_apigatewayv2_route" "accounting" {
  for_each = toset(local.accounting_routes)

  api_id             = aws_apigatewayv2_api.this.id
  route_key          = each.value
  target             = "integrations/${aws_apigatewayv2_integration.accounting.id}"
  authorization_type = "JWT"
  authorizer_id      = aws_apigatewayv2_authorizer.cognito.id
}
