output "insights_ecr_repository_url" {
  description = "Full ECR repository URI for the insights Lambda container image (no tag included)"
  value       = aws_ecr_repository.insights.repository_url
  sensitive   = true
}
