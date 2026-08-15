output "manage_user_ecr_repository_url" {
  description = "Full ECR repository URI for the manage-user Lambda container image (no tag included)"
  value       = aws_ecr_repository.manage_user.repository_url
  sensitive   = true
}
