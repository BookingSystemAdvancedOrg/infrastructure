output "tenant_purge_ecr_repository_url" {
  description = "Full ECR repository URI for the tenant-purge Lambda container image (no tag included)"
  value       = aws_ecr_repository.tenant_purge.repository_url
  sensitive   = true
}
