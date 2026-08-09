output "function_name" {
  description = "Name of the StripeWebhookFn Lambda"
  value       = aws_lambda_function.this.function_name
}

output "function_arn" {
  description = "ARN of the StripeWebhookFn Lambda"
  value       = aws_lambda_function.this.arn
}

output "invoke_arn" {
  description = "Invoke ARN of the StripeWebhookFn Lambda — for wiring into API Gateway or a Function URL later"
  value       = aws_lambda_function.this.invoke_arn
}

output "function_url" {
  description = "Public HTTPS endpoint for this Lambda - register this as the webhook destination in the Stripe Dashboard (Developers > Webhooks)"
  value       = aws_lambda_function_url.this.function_url
}
