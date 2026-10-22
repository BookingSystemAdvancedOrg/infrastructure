output "link_key_secret_arn" {
  description = "ARN of the marketing link HMAC key. The notification Lambda reads it to sign the guest's withdrawal link in booking confirmations (root privacy-consent.tf)."
  value       = aws_secretsmanager_secret.link_key.arn
}
