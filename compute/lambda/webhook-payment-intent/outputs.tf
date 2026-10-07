output "function_name" {
  description = "Name of the WebhookPaymentIntentFn Lambda"
  value       = aws_lambda_function.this.function_name
}

output "function_arn" {
  description = "ARN of the WebhookPaymentIntentFn Lambda"
  value       = aws_lambda_function.this.arn
}

output "function_url" {
  description = "Public Function URL of the WebhookPaymentIntentFn Lambda - registered with Stripe as the order-payment webhook endpoint (payments/stripe)"
  value       = aws_lambda_function_url.this.function_url
}
