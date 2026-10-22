output "guest_privacy_ecr_repository_url" {
  description = "Full ECR repository URI for the guest-privacy Lambda container image (no tag included)"
  value       = aws_ecr_repository.guest_privacy.repository_url
  sensitive   = true
}
