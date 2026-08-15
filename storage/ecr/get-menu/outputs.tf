output "get_menu_ecr_repository_url" {
  description = "Full ECR repository URI for the get-menu Lambda container image (no tag included)"
  value       = aws_ecr_repository.get_menu.repository_url
  sensitive   = true
}
