output "catering_customer_ecr_repository_url" {
  description = "Full ECR repository URI for the catering-customer Lambda container image (no tag included)"
  value       = aws_ecr_repository.catering_customer.repository_url
  sensitive   = true
}
