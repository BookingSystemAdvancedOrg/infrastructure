output "manage_auth_ecr_repository_url" {
  description = "Full ECR repository URI for the manage-auth Lambda container image (no tag included)"
  value       = aws_ecr_repository.manage_auth.repository_url
  sensitive   = true
}
