output "catering_document_ecr_repository_url" {
  description = "Full ECR repository URI for the catering-document Lambda container image (no tag included)"
  value       = aws_ecr_repository.catering_document.repository_url
  sensitive   = true
}
