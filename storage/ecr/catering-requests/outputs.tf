output "catering_requests_ecr_repository_url" {
  description = "Full ECR repository URI for the catering-requests Lambda container image (no tag included)"
  value       = aws_ecr_repository.catering_requests.repository_url
  sensitive   = true
}
