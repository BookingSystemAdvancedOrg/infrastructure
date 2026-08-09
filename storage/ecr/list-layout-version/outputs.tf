output "list_layout_version_ecr_repository_url" {
  description = "Full ECR repository URI for the list-layout-version Lambda container image (no tag included)"
  value       = aws_ecr_repository.list_layout_version.repository_url
  sensitive   = true
}
