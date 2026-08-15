output "identity_arn" {
  description = "ARN of the no-reply SES email identity"
  value       = aws_ses_email_identity.no_reply.arn
  sensitive   = true
}
