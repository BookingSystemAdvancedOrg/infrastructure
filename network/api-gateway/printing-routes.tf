# Kitchen printing (issue 2). Throttles for the printer routes are on the
# stage in main.tf (route_settings names a route by key).
#
# print-jobs (tenant pool JWT; owner or staff, owner-only writes checked in
# the handler):
#   GET  /locations/{locationId}/print            settings, printers, queue state
#   GET|POST|PUT|DELETE /locations/{locationId}/print/{proxy+}
#        status, settings, devices (add, remove, rotate, test), jobs (reprint)
#
# print-device (no JWT: the printer authenticates with HTTP Basic, its
# device id and one-time secret, checked in the handler):
#   POST   /print/cloudprnt/{deviceId}   CloudPRNT poll (status in, jobReady out)
#   GET    /print/cloudprnt/{deviceId}   fetch the job (StarPRNT bytes)
#   DELETE /print/cloudprnt/{deviceId}   confirm printed / report an error
# The stage has no access log, so a ?k= secret (fallback for firmware
# without Basic auth) is never written anywhere by API Gateway.

resource "aws_apigatewayv2_integration" "print_jobs" {
  api_id                 = aws_apigatewayv2_api.this.id
  integration_type       = "AWS_PROXY"
  integration_uri        = var.print_jobs_invoke_arn
  integration_method     = "POST" # Lambda proxy integrations always invoke via POST, regardless of the route's own method
  payload_format_version = "2.0"
}

resource "aws_lambda_permission" "print_jobs_invoke" {
  statement_id  = "AllowAPIGatewayInvoke"
  action        = "lambda:InvokeFunction"
  function_name = var.print_jobs_function_name
  qualifier     = var.lambda_alias_name
  principal     = "apigateway.amazonaws.com"
  source_arn    = "${aws_apigatewayv2_api.this.execution_arn}/*/*"
}

resource "aws_apigatewayv2_integration" "print_device" {
  api_id                 = aws_apigatewayv2_api.this.id
  integration_type       = "AWS_PROXY"
  integration_uri        = var.print_device_invoke_arn
  integration_method     = "POST"
  payload_format_version = "2.0"
}

resource "aws_lambda_permission" "print_device_invoke" {
  statement_id  = "AllowAPIGatewayInvoke"
  action        = "lambda:InvokeFunction"
  function_name = var.print_device_function_name
  qualifier     = var.lambda_alias_name
  principal     = "apigateway.amazonaws.com"
  source_arn    = "${aws_apigatewayv2_api.this.execution_arn}/*/*"
}

# --- print-jobs ---
locals {
  print_jobs_routes = ["GET /locations/{locationId}/print", "GET /locations/{locationId}/print/{proxy+}",
    "POST /locations/{locationId}/print/{proxy+}", "PUT /locations/{locationId}/print/{proxy+}",
  "DELETE /locations/{locationId}/print/{proxy+}"]
}

resource "aws_apigatewayv2_route" "print_jobs" {
  for_each = toset(local.print_jobs_routes)

  api_id             = aws_apigatewayv2_api.this.id
  route_key          = each.value
  target             = "integrations/${aws_apigatewayv2_integration.print_jobs.id}"
  authorization_type = "JWT"
  authorizer_id      = aws_apigatewayv2_authorizer.cognito.id
}

# --- print-device ---
locals {
  print_device_routes = ["POST /print/cloudprnt/{deviceId}", "GET /print/cloudprnt/{deviceId}",
  "DELETE /print/cloudprnt/{deviceId}"]
}

resource "aws_apigatewayv2_route" "print_device" {
  for_each = toset(local.print_device_routes)

  api_id             = aws_apigatewayv2_api.this.id
  route_key          = each.value
  target             = "integrations/${aws_apigatewayv2_integration.print_device.id}"
  authorization_type = "NONE"
}
