output "link_signing_key_secret_arn" {
  description = "ARN of the HMAC key secret behind customer magic links"
  value       = aws_secretsmanager_secret.link_signing_key.arn
}

output "signing_provider_secret_arn" {
  description = "ARN of the BankID signing provider credentials secret"
  value       = aws_secretsmanager_secret.signing_provider.arn
}

output "turnstile_secret_arn" {
  description = "ARN of the Cloudflare Turnstile secret key secret"
  value       = aws_secretsmanager_secret.turnstile.arn
}
