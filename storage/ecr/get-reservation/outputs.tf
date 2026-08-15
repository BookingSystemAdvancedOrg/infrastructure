output "get_reservation_ecr_repository_url" {
  description = "Full ECR repository URI for the get-reservation Lambda container image (no tag included)"
  value       = aws_ecr_repository.get_reservation.repository_url
  sensitive   = true
}
