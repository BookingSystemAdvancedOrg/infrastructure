# Routes of the ten Run 0 features (CONTRACTS.md 12.3). Each feature lists
# its routes in its own <feature-id>-routes.tf; this file is the only place
# they become API Gateway resources, so no feature edits shared routing.
#
#   auth = "jwt"      -> cognito authorizer, the feature's own integration
#   auth = "public"   -> no authorizer, the feature's own integration
#   auth = "operator" -> platform authorizer, the existing platform-tenants
#                        integration (it forwards to the feature, section 9.3)
#   throttle = "public" -> the public write routes' route_settings (main.tf)
#
# With every list empty and var.feature_integrations empty this creates
# nothing.

locals {
  feature_route_lists = {
    "meta-ads"        = local.meta_ads_routes
    "site-builder"    = local.site_builder_routes
    "guest-crm"       = local.guest_crm_routes
    "google-business" = local.google_business_routes
    "gift-cards"      = local.gift_cards_routes
    "waitlist"        = local.waitlist_routes
    "social-posting"  = local.social_posting_routes
    "personalliggare" = local.personalliggare_routes
    "accounting-sync" = local.accounting_sync_routes
    "dish-margin"     = local.dish_margin_routes
  }

  # route_key => { feature, auth, throttle }
  feature_routes = merge([
    for feature, routes in local.feature_route_lists : {
      for r in routes : r.route_key => {
        feature  = feature
        auth     = r.auth
        throttle = try(r.throttle, "")
      }
    }
  ]...)

  feature_public_throttled_routes = [for key, r in local.feature_routes : key if r.throttle == "public"]
}

resource "aws_apigatewayv2_integration" "feature" {
  for_each = var.feature_integrations

  api_id                 = aws_apigatewayv2_api.this.id
  integration_type       = "AWS_PROXY"
  integration_uri        = each.value.invoke_arn
  integration_method     = "POST" # Lambda proxy integrations always invoke via POST, regardless of the route's own method
  payload_format_version = "2.0"
}

resource "aws_lambda_permission" "feature_invoke" {
  for_each = var.feature_integrations

  statement_id  = "AllowAPIGatewayInvoke"
  action        = "lambda:InvokeFunction"
  function_name = each.value.function_name
  qualifier     = var.lambda_alias_name
  principal     = "apigateway.amazonaws.com"
  source_arn    = "${aws_apigatewayv2_api.this.execution_arn}/*/*"
}

# jwt and public routes. Separate from the operator routes below so the
# stage's depends_on (throttle = "public") never reaches platform-tenants,
# whose function depends on the stage's URL through tenant-workflows (a cycle).
resource "aws_apigatewayv2_route" "feature" {
  for_each = { for key, r in local.feature_routes : key => r if r.auth != "operator" }

  api_id             = aws_apigatewayv2_api.this.id
  route_key          = each.key
  target             = "integrations/${try(aws_apigatewayv2_integration.feature[each.value.feature].id, "missing")}"
  authorization_type = each.value.auth == "public" ? "NONE" : "JWT"
  authorizer_id      = each.value.auth == "jwt" ? aws_apigatewayv2_authorizer.cognito.id : null

  lifecycle {
    precondition {
      condition     = contains(["jwt", "public"], each.value.auth)
      error_message = "Route ${each.key} (${each.value.feature}): auth must be jwt, public or operator."
    }
    precondition {
      condition     = contains(keys(var.feature_integrations), each.value.feature)
      error_message = "Route ${each.key}: feature ${each.value.feature} lists jwt or public routes but has no api_integrations entry in its wiring output."
    }
  }
}

# Operator routes: no authorization_scopes, same as the existing
# platform_tenants routes in main.tf (Console tokens come from SRP sign-in,
# which carries no custom scope); the Lambda requires platform_admin.
resource "aws_apigatewayv2_route" "feature_operator" {
  for_each = { for key, r in local.feature_routes : key => r if r.auth == "operator" }

  api_id             = aws_apigatewayv2_api.this.id
  route_key          = each.key
  target             = "integrations/${aws_apigatewayv2_integration.platform_tenants.id}"
  authorization_type = "JWT"
  authorizer_id      = aws_apigatewayv2_authorizer.platform.id
}
