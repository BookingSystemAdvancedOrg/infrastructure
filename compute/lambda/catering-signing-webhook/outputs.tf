output "function_name" {
  description = "Name of the CateringSigningWebhookFn Lambda"
  value       = aws_lambda_function.this.function_name
}

output "function_arn" {
  description = "ARN of the CateringSigningWebhookFn Lambda"
  value       = aws_lambda_function.this.arn
}

output "invoke_arn" {
  description = "Invoke ARN of the CateringSigningWebhookFn Lambda — for wiring into API Gateway"
  value       = aws_lambda_function.this.invoke_arn
}
