output "payment_intent_ecr_repository_url" {
  description = "Full ECR repository URI for the payment-intent Lambda container image (no tag included)"
  value       = aws_ecr_repository.payment_intent.repository_url
  sensitive   = true
}
