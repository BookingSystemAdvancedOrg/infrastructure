output "create_pending_reservation_ecr_repository_url" {
  description = "Full ECR repository URI for the create-pending-reservation Lambda container image (no tag included)"
  value       = aws_ecr_repository.create_pending_reservation.repository_url
  sensitive   = true
}
