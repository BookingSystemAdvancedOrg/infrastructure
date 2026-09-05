
variable "environment" {
  type        = string
  description = "The environment being deployed (dev or prod) - used in the endpoint descriptions shown in the Stripe Dashboard"
  sensitive   = false
}
variable "api_endpoint" {
  type        = string
  description = "Base invoke URL of the HTTP API (no trailing slash) - the webhook routes are registered under it"
  sensitive   = false
}
variable "reservation_events" {
  type        = list(string)
  description = "Stripe events delivered to the reservation-payment webhook - must stay in sync with what the stripe-webhook Lambda handler actually processes"
  sensitive   = false
  # Current handler's events. The target set for the card-on-file
  # SetupIntent flow (docs/RESERVATION-PAYMENT-FLOW.md) is:
  #   "setup_intent.succeeded",
  #   "setup_intent.setup_failed",
  #   "payment_intent.succeeded",
  #   "payment_intent.payment_failed",
  # Switch this list and the handler in the SAME release - subscribing to
  # events the deployed handler errors on makes Stripe retry until the
  # endpoint is flagged. Reservations are deliberately card-only: Swish is
  # push-only (no merchant-initiated later charge) and Klarna underwrites
  # per-purchase - neither can express "0 kr now, maybe a fee later".
  default = [
    "checkout.session.completed",
    "payment_intent.succeeded",
    "payment_intent.payment_failed",
  ]
}
variable "order_events" {
  type        = list(string)
  description = "Stripe events delivered to the order-payment webhook - must stay in sync with what the webhook-payment-intent Lambda handler actually processes"
  sensitive   = false
  default = [
    "checkout.session.completed",
    "checkout.session.expired",
    # Swish/Klarna (and other redirect/async methods) can confirm or fail
    # AFTER the Checkout session completes - for them, these two are the
    # real payment outcome, not checkout.session.completed (whose
    # payment_status will be "unpaid" until the async result lands). The
    # handler must only confirm the order on session.completed when
    # payment_status == "paid", and treat async_payment_succeeded/failed as
    # the deciding events otherwise.
    "checkout.session.async_payment_succeeded",
    "checkout.session.async_payment_failed",
    "charge.refunded",
  ]
}
