output "cancel_reservation_ecr_repository_url" {
  description = "Full ECR repository URI for the cancel-reservation Lambda container image (no tag included)"
  value       = aws_ecr_repository.cancel_reservation.repository_url
  sensitive   = true
}
