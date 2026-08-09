output "publish_layout_ecr_repository_url" {
  description = "Full ECR repository URI for the publish-layout Lambda container image (no tag included)"
  value       = aws_ecr_repository.publish_layout.repository_url
  sensitive   = true
}
