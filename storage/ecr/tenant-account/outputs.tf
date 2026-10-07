output "tenant_account_ecr_repository_url" {
  description = "Full ECR repository URI for the tenant-account Lambda container image (no tag included)"
  value       = aws_ecr_repository.tenant_account.repository_url
  sensitive   = true
}
