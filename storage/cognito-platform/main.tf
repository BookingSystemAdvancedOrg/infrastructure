# The OPERATOR user pool: you, the people running the SaaS. Separate from
# the tenant pool on purpose - a tenant user can never be granted platform
# rights by a group change or a bug in manage-user, because platform
# routes only accept tokens issued by THIS pool (second JWT authorizer in
# network/api-gateway) carrying the platform/admin scope.
#
# Login is Cognito's hosted login page (authorization code + PKCE) from the
# platform admin app - no backend login proxy, no client secret in a
# browser, and Cognito enforces the TOTP MFA itself.

data "aws_caller_identity" "current" {}
data "aws_region" "current" {}

locals {
  prefix = var.environment == "prod" ? "" : "${var.environment}-"
}

resource "aws_cognito_user_pool" "this" {
  name = "${local.prefix}platform-operator-pool"

  admin_create_user_config {
    allow_admin_create_user_only = true

    invite_message_template {
      email_subject = "Plattformsåtkomst - operatörskonto"
      email_message = "Hej!<br><br>Ditt operatörskonto i Booqy Console är skapat.<br>Logga in på <a href=\"${var.console_url}\">${var.console_url}</a> med användarnamnet {username} och det tillfälliga lösenordet <b>{####}</b>.<br>Du väljer ett eget lösenord och sätter upp MFA (TOTP) vid första inloggningen."
      sms_message   = "{username} {####}"
    }
  }

  username_attributes      = ["email"]
  auto_verified_attributes = ["email"]

  # Every operator can create, suspend and offboard customers - MFA is not
  # optional here.
  mfa_configuration = "ON"
  software_token_mfa_configuration {
    enabled = true
  }

  password_policy {
    minimum_length                   = 14
    require_lowercase                = true
    require_uppercase                = true
    require_numbers                  = true
    require_symbols                  = true
    temporary_password_validity_days = 3
  }

  account_recovery_setting {
    recovery_mechanism {
      name     = "verified_email"
      priority = 1
    }
  }

  # Same switch as the tenant pool (var.invites_via_ses): through the
  # platform's SES identity instead of Cognito's capped built-in sender.
  dynamic "email_configuration" {
    for_each = var.invites_via_ses ? [1] : []
    content {
      email_sending_account = "DEVELOPER"
      source_arn            = var.ses_identity_arn
      from_email_address    = var.from_address
    }
  }

  # "Forgot password" emails a link to Booqy Console's /reset-password page
  # (compute/lambda/cognito-custom-message) - only with SES, as Cognito
  # refuses a custom email from a trigger when it sends itself. Without SES
  # the email shows the plain code, which Booqy Console also takes.
  dynamic "lambda_config" {
    for_each = var.invites_via_ses ? [1] : []
    content {
      custom_message = var.custom_message_lambda_arn
    }
  }

  deletion_protection = "ACTIVE"

  tags = {
    Environment = var.environment
  }
}

# Hosted login lives on a Cognito prefix domain - no certificate or DNS
# needed. The account ID keeps the prefix unique per AWS account.
resource "aws_cognito_user_pool_domain" "this" {
  domain       = "${local.prefix}bsa-ops-${data.aws_caller_identity.current.account_id}"
  user_pool_id = aws_cognito_user_pool.this.id
}

# platform/admin is the scope every /platform/* route requires
# (authorization_scopes in network/api-gateway) - checked by API Gateway
# before any Lambda runs.
resource "aws_cognito_resource_server" "platform" {
  identifier   = "platform"
  name         = "Platform API"
  user_pool_id = aws_cognito_user_pool.this.id

  scope {
    scope_name        = "admin"
    scope_description = "Create, change, suspend and offboard tenants"
  }
}

resource "aws_cognito_user_pool_client" "platform_admin" {
  name         = "${local.prefix}platform-admin-app"
  user_pool_id = aws_cognito_user_pool.this.id

  # Public SPA client: authorization code + PKCE, no secret.
  generate_secret                      = false
  allowed_oauth_flows_user_pool_client = true
  allowed_oauth_flows                  = ["code"]
  allowed_oauth_scopes                 = concat(["openid", "email", "profile"], aws_cognito_resource_server.platform.scope_identifiers)
  supported_identity_providers         = ["COGNITO"]
  callback_urls                        = [for url in var.app_urls : "${url}/auth/callback"]
  logout_urls                          = [for url in var.app_urls : "${url}/"]

  explicit_auth_flows = [
    "ALLOW_USER_SRP_AUTH",
    "ALLOW_REFRESH_TOKEN_AUTH",
  ]

  access_token_validity  = 1
  id_token_validity      = 1
  refresh_token_validity = 8

  token_validity_units {
    access_token  = "hours"
    id_token      = "hours"
    refresh_token = "hours"
  }

  enable_token_revocation       = true
  prevent_user_existence_errors = "ENABLED"
}

resource "aws_cognito_user_group" "platform_admin" {
  name         = "platform_admin"
  user_pool_id = aws_cognito_user_pool.this.id
  description  = "Platform operator - manages tenants through /platform/*"
}

# One account per address in var.operator_emails. No temporary_password:
# Cognito generates a random one and emails it, so there is no shared
# bootstrap password anywhere. Removing an address deletes that account on
# the next apply - that is how an operator is offboarded.
resource "aws_cognito_user" "operator" {
  for_each = toset(var.operator_emails)

  user_pool_id = aws_cognito_user_pool.this.id
  username     = each.value

  attributes = {
    email          = each.value
    email_verified = true
  }

  desired_delivery_mediums = ["EMAIL"]

  lifecycle {
    ignore_changes = [attributes]
  }
}

# Cognito invokes the custom message trigger for the emails it sends.
resource "aws_lambda_permission" "custom_message" {
  statement_id  = "AllowCognitoInvoke"
  action        = "lambda:InvokeFunction"
  function_name = var.custom_message_function_name
  qualifier     = var.lambda_alias_name
  principal     = "cognito-idp.amazonaws.com"
  source_arn    = aws_cognito_user_pool.this.arn
}

resource "aws_cognito_user_in_group" "operator" {
  for_each = toset(var.operator_emails)

  user_pool_id = aws_cognito_user_pool.this.id
  group_name   = aws_cognito_user_group.platform_admin.name
  username     = aws_cognito_user.operator[each.key].username
}
