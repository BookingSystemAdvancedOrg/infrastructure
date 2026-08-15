output "manage_layout_element_ecr_repository_url" {
  description = "Full ECR repository URI for the manage-layout-element Lambda container image (no tag included)"
  value       = aws_ecr_repository.manage_layout_element.repository_url
  sensitive   = true
}
