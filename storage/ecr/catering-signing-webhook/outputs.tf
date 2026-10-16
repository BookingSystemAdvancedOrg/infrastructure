output "catering_signing_webhook_ecr_repository_url" {
  description = "Full ECR repository URI for the catering-signing-webhook Lambda container image (no tag included)"
  value       = aws_ecr_repository.catering_signing_webhook.repository_url
  sensitive   = true
}
