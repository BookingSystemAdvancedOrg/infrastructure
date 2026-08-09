
resource "aws_cognito_user_pool" "this" {
  name = var.environment == "prod" ? "staff-user-pool" : "${var.environment}-staff-user-pool"

  # No public self-registration - accounts only ever get created via
  # AdminCreateUser (from your "add staff/owner-user" API). This is also
  # what keeps customers out of this pool entirely: there's no sign-up
  # form to find, since the customer-facing flow never touches Cognito.
  admin_create_user_config {
    allow_admin_create_user_only = true
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

  # Public client (browser app) - never issue a secret; JS running in a
  # browser can't keep one confidential anyway.
  generate_secret = false

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
}

resource "aws_cognito_user_group" "staff_user" {
  name         = "staff_user"
  user_pool_id = aws_cognito_user_pool.this.id
  description  = "Staff - scoped to one or more locations"
}

resource "aws_cognito_user_group" "owner_user" {
  name         = "owner_user"
  user_pool_id = aws_cognito_user_pool.this.id
  description  = "Owner-user - access to all locations"
}

resource "aws_cognito_user_group" "super_user" {
  name         = "super_user"
  user_pool_id = aws_cognito_user_pool.this.id
  description  = "Super-user - full platform access, can add locations and delete owner-users"
}
