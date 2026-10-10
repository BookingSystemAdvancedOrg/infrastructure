output "link_signing_key_secret_arn" {
  description = "ARN of the reservation manage-link signing key secret"
  value       = aws_secretsmanager_secret.link_signing_key.arn
}
