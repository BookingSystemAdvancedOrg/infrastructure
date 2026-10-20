output "finance_rollup_ecr_repository_url" {
  description = "Full ECR repository URI for the finance-rollup Lambda container image (no tag included)"
  value       = aws_ecr_repository.finance_rollup.repository_url
  sensitive   = true
}
