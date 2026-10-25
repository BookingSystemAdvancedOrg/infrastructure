output "repository_url" {
  description = "URL of the function's ECR repository"
  value       = aws_ecr_repository.this.repository_url
  sensitive   = true
}
