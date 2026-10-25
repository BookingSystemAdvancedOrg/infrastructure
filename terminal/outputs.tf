output "function_name" {
  description = "terminal-payments function name"
  value       = aws_lambda_function.fn.function_name
}

output "alias_name" {
  description = "Live alias name"
  value       = aws_lambda_alias.live.name
}

output "alias_invoke_arn" {
  description = "Live alias invoke ARN (API Gateway integration)"
  value       = aws_lambda_alias.live.invoke_arn
}

output "role_name" {
  description = "Execution role name"
  value       = aws_iam_role.fn.name
}

output "webhook_url" {
  description = "Function URL registered as the terminal Stripe endpoint"
  value       = aws_lambda_function_url.webhook.function_url
}
