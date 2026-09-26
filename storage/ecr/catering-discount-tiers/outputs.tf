output "catering_discount_tiers_ecr_repository_url" {
  description = "Full ECR repository URI for the catering-discount-tiers Lambda container image (no tag included)"
  value       = aws_ecr_repository.catering_discount_tiers.repository_url
  sensitive   = true
}
