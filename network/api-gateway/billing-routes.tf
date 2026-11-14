# Booqy's own subscription in admin (Inställningar, Abonnemang) and the
# restaurant terms: the open invoices, a Stripe Checkout page (setup mode,
# platform account) to add the card that is charged automatically, and
# accepting Allmänna villkor för restauranger. Same Lambda, integration and
# invoke permission as the other /tenant routes (tenant-account); owner_user
# is checked in the handler.
resource "aws_apigatewayv2_route" "tenant_billing" {
  api_id             = aws_apigatewayv2_api.this.id
  route_key          = "GET /tenant/billing"
  target             = "integrations/${aws_apigatewayv2_integration.tenant_account.id}"
  authorization_type = "JWT"
  authorizer_id      = aws_apigatewayv2_authorizer.cognito.id
}

resource "aws_apigatewayv2_route" "tenant_billing_card_session" {
  api_id             = aws_apigatewayv2_api.this.id
  route_key          = "POST /tenant/billing/card-session"
  target             = "integrations/${aws_apigatewayv2_integration.tenant_account.id}"
  authorization_type = "JWT"
  authorizer_id      = aws_apigatewayv2_authorizer.cognito.id
}

resource "aws_apigatewayv2_route" "tenant_terms_accept" {
  api_id             = aws_apigatewayv2_api.this.id
  route_key          = "POST /tenant/terms/accept"
  target             = "integrations/${aws_apigatewayv2_integration.tenant_account.id}"
  authorization_type = "JWT"
  authorizer_id      = aws_apigatewayv2_authorizer.cognito.id
}
