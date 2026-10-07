
output "reservation_webhook_secret_arn" {
  description = "ARN of the Secrets Manager secret holding the reservation endpoint's signing secret - passed to StripeWebhookFn, which reads the whsec_ value at runtime"
  value       = aws_secretsmanager_secret.webhook["reservation"].arn
}

output "order_webhook_secret_arn" {
  description = "ARN of the Secrets Manager secret holding the order endpoint's signing secret - passed to WebhookPaymentIntentFn, which reads the whsec_ value at runtime"
  value       = aws_secretsmanager_secret.webhook["order"].arn
}

output "reservation_webhook_url" {
  description = "URL registered with Stripe for reservation-payment events (the receiving Lambda's Function URL; registration itself is done by Terraform)"
  value       = stripe_webhook_endpoint.reservation.url
}

output "order_webhook_url" {
  description = "URL registered with Stripe for order-payment events (the receiving Lambda's Function URL; registration itself is done by Terraform)"
  value       = stripe_webhook_endpoint.order.url
}

output "catering_webhook_secret_arn" {
  description = "ARN of the Secrets Manager secret holding the catering endpoint's signing secret - passed to CateringStripeWebhookFn, which reads the whsec_ value at runtime"
  value       = aws_secretsmanager_secret.webhook["catering"].arn
}

output "catering_webhook_url" {
  description = "URL registered with Stripe for catering payment and invoice events (the receiving Lambda's Function URL; registration itself is done by Terraform)"
  value       = stripe_webhook_endpoint.catering.url
}

output "platform_connect_webhook_secret_arn" {
  description = "ARN of the secret holding the platform Connect endpoint's signing secret - read by PlatformStripeWebhookFn for /connect"
  value       = aws_secretsmanager_secret.webhook["platform-connect"].arn
}

output "platform_billing_webhook_secret_arn" {
  description = "ARN of the secret holding the platform billing endpoint's signing secret - read by PlatformStripeWebhookFn for /billing"
  value       = aws_secretsmanager_secret.webhook["platform-billing"].arn
}
