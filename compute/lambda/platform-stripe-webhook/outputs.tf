output "function_name" {
  description = "Name of the PlatformStripeWebhookFn Lambda"
  value       = aws_lambda_function.this.function_name
}

output "function_arn" {
  description = "ARN of the PlatformStripeWebhookFn Lambda"
  value       = aws_lambda_function.this.arn
}

output "invoke_arn" {
  description = "Invoke ARN of the PlatformStripeWebhookFn Lambda — for wiring into API Gateway"
  value       = aws_lambda_function.this.invoke_arn
}

output "function_url" {
  description = "Public Function URL of the PlatformStripeWebhookFn Lambda - payments/stripe registers <url>connect and <url>billing as the platform endpoints"
  value       = aws_lambda_function_url.this.function_url
}

output "alias_name" {
  description = "Name of the alias every caller invokes"
  value       = aws_lambda_alias.live.name
}

output "alias_arn" {
  description = "Qualified ARN of the live alias - use this (not function_arn) as an invoke / event source / Scheduler target"
  value       = aws_lambda_alias.live.arn
}

output "alias_invoke_arn" {
  description = "Invoke ARN of the live alias - for API Gateway integrations"
  value       = aws_lambda_alias.live.invoke_arn
}
