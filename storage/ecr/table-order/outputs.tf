output "table_order_ecr_repository_url" {
  description = "Full ECR repository URI for the table-order Lambda container image (no tag included)"
  value       = aws_ecr_repository.table_order.repository_url
  sensitive   = true
}
