
# Stripe webhook endpoints, managed here instead of clicked together in the
# Stripe Dashboard - forking this repo for a new customer no longer involves
# any manual webhook setup: `terraform apply` creates the endpoints in
# whichever Stripe account the provider's API key belongs to (test mode for
# dev, live mode for prod), and each endpoint's signing secret flows straight
# into the receiving Lambda's environment in the same apply.
#
# The endpoint URLs point at API Gateway routes, NOT Lambda Function URLs,
# on purpose: a Function URL is derived from the Lambda function, and that
# function's environment needs the endpoint's signing secret - a hard cycle
# Terraform refuses to plan. The HTTP API's invoke URL depends only on the
# API/stage resources, so "API -> endpoint -> Lambda -> route" stays acyclic
# and everything lands in one apply. Payload format 2.0 on those routes
# delivers the exact same event shape as a Function URL, so the handlers
# didn't have to change.

terraform {
  required_providers {
    stripe = {
      source = "lukasaron/stripe"
    }
  }
}

# Reservation payments - received by StripeWebhookFn. Defaults match the
# events the previously hand-created Dashboard endpoint subscribed to.
resource "stripe_webhook_endpoint" "reservation" {
  url            = "${var.api_endpoint}/webhooks/stripe/reservation"
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
  url            = "${var.api_endpoint}/webhooks/stripe/order"
  description    = "${var.environment} order payments -> webhook-payment-intent Lambda"
  enabled_events = var.order_events
}
