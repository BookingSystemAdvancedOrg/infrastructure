output "notification_ecr_repository_url" {
  description = "Full ECR repository URI for the notification Lambda container image (no tag included)"
  value       = aws_ecr_repository.notification.repository_url
  sensitive   = true
}
