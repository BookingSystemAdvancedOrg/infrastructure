output "reservation_reminders_ecr_repository_url" {
  description = "Full ECR repository URI for the reservation-reminders Lambda container image (no tag included)"
  value       = aws_ecr_repository.reservation_reminders.repository_url
  sensitive   = true
}
