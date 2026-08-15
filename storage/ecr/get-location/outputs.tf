output "get_location_ecr_repository_url" {
  description = "Full ECR repository URI for the get-location Lambda container image (no tag included)"
  value       = aws_ecr_repository.get_location.repository_url
  sensitive   = true
}
