# Platform-wide secrets - one per environment, shared by every tenant.
#
# The Stripe key here belongs to YOUR platform Stripe account. Restaurants
# are Stripe Connect accounts under it: every Lambda calls Stripe with this
# key plus the tenant's connected account id (Stripe-Account header), so no
# restaurant's own key is ever stored anywhere. That also makes this the
# single most sensitive secret in the stack - it can act on every connected
# account - which is why it lives only here (readable by the specific roles
# granted GetSecretValue on it) and never in a Lambda environment variable.
#
# Seeded with the pipeline's key so the first deploy works; replace it with
# a RESTRICTED key (docs/PLATFORM-SETUP.md lists the permissions) - Terraform
# won't overwrite the rotated value.

locals {
  prefix                  = var.environment == "prod" ? "" : "${var.environment}-"
  recovery_window_in_days = var.environment == "prod" ? 30 : 7
}

resource "aws_secretsmanager_secret" "stripe" {
  name                    = "${local.prefix}stripe/api-key"
  description             = "Platform Stripe API key (JSON {\"apiKey\": \"rk_...\"}) - Connect platform account; replace the seeded secret key with a restricted key"
  recovery_window_in_days = local.recovery_window_in_days

  tags = {
    Environment = var.environment
  }
}

resource "aws_secretsmanager_secret_version" "stripe" {
  secret_id     = aws_secretsmanager_secret.stripe.id
  secret_string = jsonencode({ apiKey = var.stripe_secret_key })

  # Rotated by hand to a restricted key after first deploy - never revert it.
  lifecycle {
    ignore_changes = [secret_string]
  }
}
