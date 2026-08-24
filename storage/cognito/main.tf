
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

  lifecycle {
    # This group must always exist - accidentally destroying it would
    # strip super_user membership from everyone in super_admin_emails.
    prevent_destroy = true
  }
}

# --- Bootstrap super_user accounts -----------------------------------------
#
# One aws_cognito_user + one aws_cognito_user_in_group per email in
# super_admin_emails. AdminCreateUser-style: account is created in
# FORCE_CHANGE_PASSWORD status with a fixed, shared temporary password
# (var.super_admin_temp_password - "Helloworld123!" by default, chosen to
# satisfy this pool's password_policy), no email sent (message_action =
# SUPPRESS). Whoever owns each address logs in once with that temp
# password, Cognito forces them to set a real one, and from then on
# `ignore_changes` keeps Terraform from ever touching their attributes or
# password again.
#
# NOTE: a fixed, shared, non-secret temp password means anyone who knows
# it (it's in this repo) can attempt the FORCE_CHANGE_PASSWORD login for
# any address in super_admin_emails until that person actually logs in
# and rotates it - there is no per-user secret gating that first login.
# Get each new super_admin logged in (and thus off the shared password)
# promptly after apply.
#
# Removing an email from the list removes that person's user_in_group
# membership AND the aws_cognito_user account itself on next apply - this
# is destructive by design so off-boarding staff actually revokes access.
# Add new super-admins by adding emails, never by editing this block.

resource "aws_cognito_user" "super_admin" {
  for_each = toset(var.super_admin_emails)

  user_pool_id = aws_cognito_user_pool.this.id
  username     = each.value

  attributes = {
    email          = each.value
    email_verified = true
  }

  temporary_password   = var.super_admin_temp_password
  message_action       = "SUPPRESS"
  force_alias_creation = false

  lifecycle {
    ignore_changes = [attributes, temporary_password]
  }
}

resource "aws_cognito_user_in_group" "super_admin_membership" {
  for_each = toset(var.super_admin_emails)

  user_pool_id = aws_cognito_user_pool.this.id
  group_name   = aws_cognito_user_group.super_user.name
  username     = aws_cognito_user.super_admin[each.key].username
}
