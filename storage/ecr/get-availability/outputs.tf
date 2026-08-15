output "get_availability_ecr_repository_url" {
  description = "Full ECR repository URI for the get-availability Lambda container image (no tag included)"
  value       = aws_ecr_repository.get_availability.repository_url
  sensitive   = true
}
