# Booqy Console's help assistant (help-assistant module). Operator tokens
# (platform authorizer, same as the platform_tenants routes) go straight to the
# help-assistant integration instead of platform-tenants; the Lambda requires
# the platform_admin group itself. Nothing is created until the feature has
# its integration (var.feature_integrations["help-assistant"]).
locals {
  help_assistant_operator_routes = ["GET /platform/help-assistant", "POST /platform/help-assistant/answers"]
}

resource "aws_apigatewayv2_route" "help_assistant_operator" {
  for_each = contains(keys(var.feature_integrations), "help-assistant") ? toset(local.help_assistant_operator_routes) : toset([])

  api_id             = aws_apigatewayv2_api.this.id
  route_key          = each.value
  target             = "integrations/${aws_apigatewayv2_integration.feature["help-assistant"].id}"
  authorization_type = "JWT"
  authorizer_id      = aws_apigatewayv2_authorizer.platform.id
}
