# Booqy Console's Reports page (support-reports module). Operator tokens
# (platform authorizer, same as the platform_tenants routes) go straight to the
# support-reports integration instead of platform-tenants; the Lambda requires
# the platform_admin group itself. Nothing is created until the feature has
# its integration (var.feature_integrations["support-reports"]).
locals {
  support_reports_operator_routes = [
    "GET /platform/support/reports",
    "POST /platform/support/reports/{reportId}/handled",
  ]
}

resource "aws_apigatewayv2_route" "support_reports_operator" {
  for_each = contains(keys(var.feature_integrations), "support-reports") ? toset(local.support_reports_operator_routes) : toset([])

  api_id             = aws_apigatewayv2_api.this.id
  route_key          = each.value
  target             = "integrations/${aws_apigatewayv2_integration.feature["support-reports"].id}"
  authorization_type = "JWT"
  authorizer_id      = aws_apigatewayv2_authorizer.platform.id
}
