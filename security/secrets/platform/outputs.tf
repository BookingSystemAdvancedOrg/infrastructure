output "stripe_secret_arn" {
  description = "ARN of the platform Stripe API key secret - every Lambda that calls Stripe reads it at cold start"
  value       = aws_secretsmanager_secret.stripe.arn
}
