output "no_show_check_ecr_repository_url" {
  description = "Full ECR repository URI for the no-show-check Lambda container image (no tag included)"
  value       = aws_ecr_repository.no_show_check.repository_url
  sensitive   = true
}
