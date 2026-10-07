output "dlq_replay_ecr_repository_url" {
  description = "Full ECR repository URI for the dlq-replay Lambda container image (no tag included)"
  value       = aws_ecr_repository.dlq_replay.repository_url
  sensitive   = true
}
