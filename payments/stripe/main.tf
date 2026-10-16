
# Stripe webhook endpoints, managed here instead of clicked together in the
# Stripe Dashboard: `terraform apply` creates them in the PLATFORM Stripe
# account the provider's API key belongs to (sandbox for dev, live for prod).
#
# Stripe Connect: restaurants are connected accounts under the platform, and
# their Checkout Sessions, PaymentIntents and invoices live ON their
# accounts (direct charges with the Stripe-Account header). Events about
# those objects only reach endpoints created with connect = true, and each
# such event carries a top-level `account` (acct_...) - that's how a handler
# finds the tenant (tenant table, STRIPE_ACCOUNT#<acct> row). So the
# reservation, order and catering endpoints are Connect endpoints, one per
# environment for ALL tenants - adding a restaurant never adds an endpoint.
#
# Connect endpoints on a live key also receive test-mode events from
# connected accounts' sandboxes: handlers must check event.livemode.
#
# Each endpoint points straight at its Lambda's Function URL - there is no
# API Gateway in front of any Stripe webhook. That ordering decides where
# the signing secret can live:
#
#   Lambda -> Function URL -> Stripe endpoint -> signing secret
#
# The secret only exists after the endpoint, and the endpoint only after the
# URL, so the secret can't be put in the Lambda's environment (that would be
# a cycle). Instead each endpoint's secret is written into a Secrets Manager
# secret created HERE, whose ARN - which doesn't depend on the endpoint -
# goes into the Lambda's environment. One apply still wires everything up,
# and the whsec_ value never leaves Terraform state and Secrets Manager.
terraform {
  required_providers {
    stripe = {
      source = "lukasaron/stripe"
    }
    aws = {
      source = "hashicorp/aws"
    }
  }
}

# Reservation payments - received by StripeWebhookFn. Defaults match the
# events the previously hand-created Dashboard endpoint subscribed to.
resource "stripe_webhook_endpoint" "reservation" {
  connect        = true
  url            = var.reservation_webhook_url
  description    = "${var.environment} reservation payments -> stripe-webhook Lambda"
  enabled_events = var.reservation_events
}

# Order (food) payments - received by WebhookPaymentIntentFn.
# checkout.session.expired is the abandoned-checkout cleanup signal;
# charge.refunded keeps the order table truthful even for refunds issued
# from the Stripe Dashboard. payment_intent.payment_failed is deliberately
# NOT here: with hosted Checkout it fires on every declined attempt while
# the customer can still retry on the Stripe page - acting on it would
# cancel orders that get paid seconds later.
resource "stripe_webhook_endpoint" "order" {
  connect        = true
  url            = var.order_webhook_url
  description    = "${var.environment} order payments -> webhook-payment-intent Lambda"
  enabled_events = var.order_events
}

# Catering payments and invoices - received by CateringStripeWebhookFn. Its
# own endpoint (and signing secret) rather than a share of the order
# endpoint, so a catering bug or a slow catering handler can never get the
# food-order endpoint disabled by Stripe's failure backoff.
resource "stripe_webhook_endpoint" "catering" {
  connect        = true
  url            = var.catering_webhook_url
  description    = "${var.environment} catering payments + invoices -> catering-stripe-webhook Lambda"
  enabled_events = var.catering_events
}

# Platform events, both delivered to platform-stripe-webhook (one function,
# two paths, two signing secrets):
#
#   connect - a restaurant's connected account changed: onboarding finished
#             (charges_enabled), details due, or the restaurant disconnected
#             from the platform. Keeps PROFILE.stripe.* in the tenant table
#             truthful without anyone polling Stripe.
#   billing - YOUR platform account's own subscriptions: the restaurant's
#             SaaS plan. A subscription change (e.g. quantity 1 -> 2
#             locations from the Stripe customer portal) updates the
#             tenant's plan and maxLocations - an upgrade with no deploy and
#             no operator involved. Silent until you sell plans through
#             Stripe Billing.
resource "stripe_webhook_endpoint" "platform_connect" {
  connect        = true
  url            = "${var.platform_webhook_url}connect"
  description    = "${var.environment} connected-account lifecycle -> platform-stripe-webhook Lambda"
  enabled_events = var.platform_connect_events
}

resource "stripe_webhook_endpoint" "platform_billing" {
  connect        = false
  url            = "${var.platform_webhook_url}billing"
  description    = "${var.environment} platform SaaS subscriptions -> platform-stripe-webhook Lambda"
  enabled_events = var.platform_billing_events
}

# ---------------------------------------------------------------------------
# Signing secrets, one Secrets Manager secret per endpoint. The secret
# (container) has no dependency on Stripe, so its ARN can sit in the Lambda's
# environment; the version holds the endpoint's whsec_ value and is
# replaced automatically if Stripe ever re-creates an endpoint.

locals {
  secret_prefix           = var.environment == "prod" ? "" : "${var.environment}-"
  recovery_window_in_days = var.environment == "prod" ? 30 : 7
  webhook_endpoints = {
    reservation      = stripe_webhook_endpoint.reservation
    order            = stripe_webhook_endpoint.order
    catering         = stripe_webhook_endpoint.catering
    platform-connect = stripe_webhook_endpoint.platform_connect
    platform-billing = stripe_webhook_endpoint.platform_billing
  }
}

resource "aws_secretsmanager_secret" "webhook" {
  for_each = toset(["reservation", "order", "catering", "platform-connect", "platform-billing"])

  name                    = "${local.secret_prefix}stripe/webhook/${each.key}"
  description             = "Signing secret (whsec_...) of the ${each.key} Stripe webhook endpoint - written by Terraform, read by the receiving Lambda"
  recovery_window_in_days = local.recovery_window_in_days

  tags = {
    Environment = var.environment
  }
}

resource "aws_secretsmanager_secret_version" "webhook" {
  for_each = local.webhook_endpoints

  secret_id     = aws_secretsmanager_secret.webhook[each.key].id
  secret_string = each.value.secret
}
