output "tenant_site_config_ecr_repository_url" {
  description = "Full ECR repository URI for the tenant-site-config Lambda container image (no tag included)"
  value       = aws_ecr_repository.tenant_site_config.repository_url
  sensitive   = true
}
