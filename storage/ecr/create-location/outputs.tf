output "create_location_ecr_repository_url" {
  description = "Full ECR repository URI for the create-location Lambda container image (no tag included)"
  value       = aws_ecr_repository.create_location.repository_url
  sensitive   = true
}
