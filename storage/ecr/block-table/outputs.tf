output "block_table_ecr_repository_url" {
  description = "Full ECR repository URI for the block-table Lambda container image (no tag included)"
  value       = aws_ecr_repository.block_table.repository_url
  sensitive   = true
}
