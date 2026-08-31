output "get_order_ecr_repository_url" {
  description = "Full ECR repository URI for the get-order Lambda container image (no tag included)"
  value       = aws_ecr_repository.get_order.repository_url
  sensitive   = true
}
