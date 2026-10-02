output "reactivate_menu_item_ecr_repository_url" {
  description = "Full ECR repository URI for the reactivate-menu-item Lambda container image (no tag included)"
  value       = aws_ecr_repository.reactivate_menu_item.repository_url
  sensitive   = true
}
