# Staff order taking at the table (Bordsbeställning). Tenant pool JWT,
# owner or staff (staff only on their assigned location, checked in the
# handler). No payment: the guest pays in the restaurant's own system and
# staff close the tab.
#
#   GET   /locations/{locationId}/table-orders           open tabs, tables (?version=N poll)
#   POST  /locations/{locationId}/table-orders           open a tab and send its first round
#   GET|POST|PATCH /locations/{locationId}/table-orders/{proxy+}
#         menu, closed, one tab, items, send, void, move, close, reopen,
#         rounds/{n}/dispatch

# --- table-order ---

resource "aws_apigatewayv2_integration" "table_order" {
  api_id                 = aws_apigatewayv2_api.this.id
  integration_type       = "AWS_PROXY"
  integration_uri        = var.table_order_invoke_arn
  integration_method     = "POST" # Lambda proxy integrations always invoke via POST, regardless of the route's own method
  payload_format_version = "2.0"
}

locals {
  table_order_methods = ["GET", "POST", "PATCH"]
}

resource "aws_apigatewayv2_route" "table_order_collection" {
  for_each = toset(local.table_order_methods)

  api_id             = aws_apigatewayv2_api.this.id
  route_key          = "${each.value} /locations/{locationId}/table-orders"
  target             = "integrations/${aws_apigatewayv2_integration.table_order.id}"
  authorization_type = "JWT"
  authorizer_id      = aws_apigatewayv2_authorizer.cognito.id
}

resource "aws_apigatewayv2_route" "table_order" {
  for_each = toset(local.table_order_methods)

  api_id             = aws_apigatewayv2_api.this.id
  route_key          = "${each.value} /locations/{locationId}/table-orders/{proxy+}"
  target             = "integrations/${aws_apigatewayv2_integration.table_order.id}"
  authorization_type = "JWT"
  authorizer_id      = aws_apigatewayv2_authorizer.cognito.id
}

resource "aws_lambda_permission" "table_order_invoke" {
  statement_id  = "AllowAPIGatewayInvoke"
  action        = "lambda:InvokeFunction"
  function_name = var.table_order_function_name
  qualifier     = var.lambda_alias_name
  principal     = "apigateway.amazonaws.com"
  source_arn    = "${aws_apigatewayv2_api.this.execution_arn}/*/*"
}
