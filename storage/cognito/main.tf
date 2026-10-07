
# The TENANT user pool: every restaurant's owners and staff, all tenants in
# one pool. Which tenant a user belongs to is the immutable custom:tenant_id
# attribute, put into every token as the tenant_id claim by the
# pre-token-generation trigger. Platform operators (you) are NOT in this
# pool - they have their own (storage/cognito-platform), so no tenant user
# can ever hold platform rights.

resource "aws_cognito_user_pool" "this" {
  name = var.environment == "prod" ? "staff-user-pool" : "${var.environment}-staff-user-pool"

  # Essentials is the lowest feature plan that lets the pre token generation
  # trigger customize ACCESS tokens (Lite only customizes ID tokens) - and
  # the access token is what the API is called with.
  user_pool_tier = "ESSENTIALS"

  # No public self-registration - accounts only ever get created via
  # AdminCreateUser (the onboarding workflow for a tenant's first owner,
  # manage-user for everyone after that). This is also what keeps customers
  # out of this pool entirely: there's no sign-up form to find, since the
  # customer-facing flow never touches Cognito.
  admin_create_user_config {
    allow_admin_create_user_only = true

    invite_message_template {
      email_subject = var.invite_email_subject
      email_message = replace(var.invite_email_message, "$${admin_app_url}", var.admin_app_url)
      sms_message   = "Din inloggning: {username} / {####}"
    }
  }

  # Which tenant the user belongs to. Immutable (mutable = false): set once
  # at AdminCreateUser and never changeable afterwards, not even by an
  # admin - moving someone to another tenant means a new account. Also left
  # out of the app client's write_attributes below, so a signed-in user
  # can't touch it either.
  schema {
    name                     = "tenant_id"
    attribute_data_type      = "String"
    mutable                  = false
    developer_only_attribute = false
    required                 = false

    string_attribute_constraints {
      min_length = 1
      max_length = 64
    }
  }

  lambda_config {
    pre_token_generation_config {
      lambda_arn     = var.pre_token_generation_lambda_arn
      lambda_version = "V2_0"
    }
  }

  # Cognito's built-in sender is capped at 50 emails/day - fine for dev,
  # not for onboarding customers. var.invites_via_ses switches invites and
  # password resets to the platform's SES identity.
  dynamic "email_configuration" {
    for_each = var.invites_via_ses ? [1] : []
    content {
      email_sending_account = "DEVELOPER"
      source_arn            = var.ses_identity_arn
      from_email_address    = var.invite_from_address
    }
  }

  # Email is the username - login is email + password directly, no
  # separate username field.
  username_attributes      = ["email"]
  auto_verified_attributes = ["email"]

  mfa_configuration = "OFF"

  password_policy {
    minimum_length    = 8
    require_lowercase = true
    require_uppercase = true
    require_numbers   = true
    require_symbols   = true
  }

  # Prevents an accidental `terraform destroy` from locking out every
  # staff member at once.
  deletion_protection = "ACTIVE"

  tags = {
    Environment = var.environment
  }
}

resource "aws_cognito_user_pool_client" "this" {
  name         = var.environment == "prod" ? "staff-app-client" : "${var.environment}-staff-app-client"
  user_pool_id = aws_cognito_user_pool.this.id

  # NOTE: generate_secret was previously false — this was a public client
  # (browser app), and JS running in a browser can't keep a secret
  # confidential. It's now true because manage-auth needs a client secret.
  # If the browser (or any other consumer) still calls this same client
  # directly, that flow is now broken: a client with a secret must send
  # SECRET_HASH on every InitiateAuth/AdminInitiateAuth call, which a
  # public JS client can't safely compute. Confirm nothing else uses this
  # client before applying, or split manage-auth onto its own client.
  generate_secret = true

  # Direct email + password login (InitiateAuth), no Hosted UI redirect.
  explicit_auth_flows = [
    "ALLOW_USER_PASSWORD_AUTH",
    "ALLOW_REFRESH_TOKEN_AUTH",
  ]

  # Access/ID tokens are short-lived - they're sent on every API request,
  # so limiting their lifetime limits how much a leaked one can be used
  # for. The 8-hour "session" instead lives on the refresh token: the
  # frontend silently uses it to mint new 1-hour access tokens throughout
  # a shift, and only a real login is required once 8 hours have passed.
  access_token_validity  = 1
  id_token_validity      = 1
  refresh_token_validity = 120 # 5 days

  token_validity_units {
    access_token  = "hours"
    id_token      = "hours"
    refresh_token = "hours"
  }

  # Avoids leaking "that email doesn't exist" vs "wrong password" on
  # failed logins - basic protection against account enumeration.
  prevent_user_existence_errors = "ENABLED"

  # What a signed-in user may change about themselves. custom:tenant_id is
  # deliberately absent (it's immutable anyway - belt and braces).
  write_attributes = ["name", "given_name", "family_name", "phone_number"]
}

resource "aws_cognito_user_group" "staff_user" {
  name         = "staff_user"
  user_pool_id = aws_cognito_user_pool.this.id
  description  = "Staff - scoped to locations of their own tenant (locationId on their user profile)"
}

resource "aws_cognito_user_group" "owner_user" {
  name         = "owner_user"
  user_pool_id = aws_cognito_user_pool.this.id
  description  = "Restaurant owner - every location of their own tenant, nothing outside it"
}

# Cognito invokes the trigger on every sign-in and token refresh.
resource "aws_lambda_permission" "pre_token_generation" {
  statement_id  = "AllowCognitoInvoke"
  action        = "lambda:InvokeFunction"
  function_name = var.pre_token_generation_function_name
  principal     = "cognito-idp.amazonaws.com"
  source_arn    = aws_cognito_user_pool.this.arn
}
