output "pre_signed_url_ecr_repository_url" {
  description = "Full ECR repository URI for the pre-signed-url Lambda container image (no tag included)"
  value       = aws_ecr_repository.pre_signed_url.repository_url
  sensitive   = true
}
