output "webhook_payment_intent_ecr_repository_url" {
  description = "Full ECR repository URI for the webhook-payment-intent Lambda container image (no tag included)"
  value       = aws_ecr_repository.webhook_payment_intent.repository_url
  sensitive   = true
}
