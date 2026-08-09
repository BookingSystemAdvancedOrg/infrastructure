output "mark_arrived_ecr_repository_url" {
  description = "Full ECR repository URI for the mark-arrived Lambda container image (no tag included)"
  value       = aws_ecr_repository.mark_arrived.repository_url
  sensitive   = true
}
