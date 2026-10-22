output "data_retention_ecr_repository_url" {
  description = "Full ECR repository URI for the data-retention Lambda container image (no tag included)"
  value       = aws_ecr_repository.data_retention.repository_url
  sensitive   = true
}
