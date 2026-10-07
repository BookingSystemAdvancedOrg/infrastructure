output "platform_tenants_ecr_repository_url" {
  description = "Full ECR repository URI for the platform-tenants Lambda container image (no tag included)"
  value       = aws_ecr_repository.platform_tenants.repository_url
  sensitive   = true
}

output "platform_tenants_ecr_repository_arn" {
  description = "ARN of the platform-tenants ECR repository - the sbs-admin pipeline pushes the image here"
  value       = aws_ecr_repository.platform_tenants.arn
}

output "platform_tenants_ecr_repository_name" {
  description = "Name of the platform-tenants ECR repository"
  value       = aws_ecr_repository.platform_tenants.name
}
