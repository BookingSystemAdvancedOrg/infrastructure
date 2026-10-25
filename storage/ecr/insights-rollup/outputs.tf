output "insights_rollup_ecr_repository_url" {
  description = "Full ECR repository URI for the insights-rollup Lambda container image (no tag included)"
  value       = aws_ecr_repository.insights_rollup.repository_url
  sensitive   = true
}
