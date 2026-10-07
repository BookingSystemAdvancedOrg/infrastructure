# Secrets for the catering workflow, in Secrets Manager rather than Lambda
# environment variables: an environment variable is readable by anyone who
# can run lambda:GetFunctionConfiguration, while each secret here is
# readable only by the specific roles granted secretsmanager:GetSecretValue
# on it (see the security/iam/catering-* modules).
#
# All of these are PLATFORM-level (one per environment, shared by every
# tenant): the platform holds one BankID signing-provider contract and one
# Turnstile widget, and a magic link carries its locationId, which already
# pins the tenant. The Stripe key moved to security/secrets/platform - with
# Stripe Connect it's the platform account's key, not a catering one.
#
# Two ways values get in:
#
#   1. Generated here     - link-signing-key. Terraform creates a random
#                           value once; ignore_changes keeps it stable.
#   2. Set by hand only   - signing-provider, turnstile. Terraform creates
#                           the empty secret; the value comes from the
#                           provider's dashboard (docs/PLATFORM-SETUP.md).
#                           Until it's set, the Lambdas that read it fail
#                           loudly.

locals {
  prefix = var.environment == "prod" ? "" : "${var.environment}-"
  # Prod keeps the full 30-day recovery window; dev deletes after 7 days so
  # a teardown/re-create cycle isn't blocked for a month.
  recovery_window_in_days = var.environment == "prod" ? 30 : 7
}

# HMAC-SHA256 key behind the customer magic links. A link carries
# requestId + HMAC(key, "<locationId>#<requestId>#<linkVersion>"), so any
# component holding this key (catering-requests, NotificationFn,
# catering-customer) can build or verify a link without the raw token ever
# being stored. Bumping a request's linkVersion revokes its old links.
resource "aws_secretsmanager_secret" "link_signing_key" {
  name                    = "${local.prefix}catering/link-signing-key"
  description             = "HMAC key for catering customer magic links"
  recovery_window_in_days = local.recovery_window_in_days

  tags = {
    Environment = var.environment
  }
}

ephemeral "aws_secretsmanager_random_password" "link_signing_key" {
  password_length     = 64
  exclude_punctuation = true
}

resource "aws_secretsmanager_secret_version" "link_signing_key" {
  secret_id                = aws_secretsmanager_secret.link_signing_key.id
  secret_string_wo         = ephemeral.aws_secretsmanager_random_password.link_signing_key.random_password
  secret_string_wo_version = 1 # bump to rotate - every existing customer link stops working
}

# BankID signing provider (Scrive / Idura / Signicat - whichever is
# contracted). Expected JSON shape, set out-of-band:
#   { "provider": "...", "clientId": "...", "clientSecret": "...",
#     "webhookSecret": "..." }
resource "aws_secretsmanager_secret" "signing_provider" {
  name                    = "${local.prefix}catering/signing-provider"
  description             = "BankID signing provider API credentials and webhook secret (JSON) - set by hand"
  recovery_window_in_days = local.recovery_window_in_days

  tags = {
    Environment = var.environment
  }
}

# Cloudflare Turnstile secret key, verified server-side by catering-requests
# on every public submit. Expected JSON: { "secretKey": "..." }
resource "aws_secretsmanager_secret" "turnstile" {
  name                    = "${local.prefix}catering/turnstile"
  description             = "Cloudflare Turnstile secret key (JSON) - set by hand"
  recovery_window_in_days = local.recovery_window_in_days

  tags = {
    Environment = var.environment
  }
}
