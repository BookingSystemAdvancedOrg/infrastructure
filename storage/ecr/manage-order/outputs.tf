output "manage_order_ecr_repository_url" {
  description = "Full ECR repository URI for the manage-order Lambda container image (no tag included)"
  value       = aws_ecr_repository.manage_order.repository_url
  sensitive   = true
}
