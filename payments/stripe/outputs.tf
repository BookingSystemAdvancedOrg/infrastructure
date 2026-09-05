
output "reservation_webhook_secret" {
  description = "Signing secret (whsec_...) of the reservation-payment endpoint - wired into StripeWebhookFn's environment, never copied anywhere by hand"
  value       = stripe_webhook_endpoint.reservation.secret
  sensitive   = true
}

output "order_webhook_secret" {
  description = "Signing secret (whsec_...) of the order-payment endpoint - wired into WebhookPaymentIntentFn's environment, never copied anywhere by hand"
  value       = stripe_webhook_endpoint.order.secret
  sensitive   = true
}

output "reservation_webhook_url" {
  description = "URL registered with Stripe for reservation-payment events (informational - registration itself is done by Terraform)"
  value       = stripe_webhook_endpoint.reservation.url
}

output "order_webhook_url" {
  description = "URL registered with Stripe for order-payment events (informational - registration itself is done by Terraform)"
  value       = stripe_webhook_endpoint.order.url
}
