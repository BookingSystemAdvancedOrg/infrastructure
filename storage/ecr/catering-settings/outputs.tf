output "catering_settings_ecr_repository_url" {
  description = "Full ECR repository URI for the catering-settings Lambda container image (no tag included)"
  value       = aws_ecr_repository.catering_settings.repository_url
  sensitive   = true
}
