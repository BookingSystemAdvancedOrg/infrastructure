output "platform_stripe_webhook_ecr_repository_url" {
  description = "Full ECR repository URI for the platform-stripe-webhook Lambda container image (no tag included)"
  value       = aws_ecr_repository.platform_stripe_webhook.repository_url
  sensitive   = true
}
