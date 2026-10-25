# DPA acceptance: the owner accepts the current personuppgiftsbiträdesavtal
# in admin. Same Lambda, integration and invoke permission as the other
# /tenant routes (main.tf, tenant-account); owner_user is checked in the
# handler.
resource "aws_apigatewayv2_route" "tenant_dpa_accept" {
  api_id             = aws_apigatewayv2_api.this.id
  route_key          = "POST /tenant/dpa/accept"
  target             = "integrations/${aws_apigatewayv2_integration.tenant_account.id}"
  authorization_type = "JWT"
  authorizer_id      = aws_apigatewayv2_authorizer.cognito.id
}
