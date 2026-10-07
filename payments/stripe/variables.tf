
variable "environment" {
  type        = string
  description = "The environment being deployed (dev or prod) - used in the endpoint descriptions shown in the Stripe Dashboard"
  sensitive   = false
}
variable "reservation_webhook_url" {
  type        = string
  description = "Function URL of the stripe-webhook Lambda - registered as the reservation-payment endpoint"
  sensitive   = false
}
variable "order_webhook_url" {
  type        = string
  description = "Function URL of the webhook-payment-intent Lambda - registered as the order-payment endpoint"
  sensitive   = false
}
variable "catering_webhook_url" {
  type        = string
  description = "Function URL of the catering-stripe-webhook Lambda - registered as the catering endpoint"
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
variable "catering_events" {
  type        = list(string)
  description = "Stripe events delivered to the catering webhook - must stay in sync with what the catering-stripe-webhook Lambda handler actually processes"
  sensitive   = false
  # Checkout (private customers, pay at signing):
  #   completed + async_payment_* decide the payment outcome (Swish/Klarna
  #   resolve asynchronously - only payment_status == "paid" confirms);
  #   expired means the customer can retry from their link - the order
  #   stays "signed", the signature is kept.
  # Invoices (Stripe Invoicing - company invoices, and the paid
  # receipt-invoice Checkout creates for private customers):
  #   finalized -> archive the PDF; paid / payment_failed / overdue /
  #   voided -> mirror invoiceStatus onto the order.
  # Refunds/credits when the restaurant cancels:
  #   credit_note.created (company), charge.refunded (private).
  default = [
    "checkout.session.completed",
    "checkout.session.expired",
    "checkout.session.async_payment_succeeded",
    "checkout.session.async_payment_failed",
    "invoice.finalized",
    "invoice.paid",
    "invoice.payment_failed",
    "invoice.overdue",
    "invoice.voided",
    "credit_note.created",
    "charge.refunded",
  ]
}
variable "platform_webhook_url" {
  type        = string
  description = "Function URL of the platform-stripe-webhook Lambda (with trailing slash) - registered as <url>connect and <url>billing"
  sensitive   = false
}
variable "platform_connect_events" {
  type        = list(string)
  description = "Connected-account lifecycle events delivered to platform-stripe-webhook /connect"
  sensitive   = false
  default = [
    "account.updated",
    "account.application.deauthorized",
  ]
}
variable "platform_billing_events" {
  type        = list(string)
  description = "Platform-account subscription events (the restaurants' SaaS plans) delivered to platform-stripe-webhook /billing"
  sensitive   = false
  default = [
    "customer.subscription.created",
    "customer.subscription.updated",
    "customer.subscription.deleted",
    "invoice.payment_failed",
  ]
}
