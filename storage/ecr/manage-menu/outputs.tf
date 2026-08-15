output "manage_menu_ecr_repository_url" {
  description = "Full ECR repository URI for the manage-menu Lambda container image (no tag included)"
  value       = aws_ecr_repository.manage_menu.repository_url
  sensitive   = true
}
