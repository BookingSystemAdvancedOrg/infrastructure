output "function_name" {
  description = "Name of the pre-token-generation Lambda"
  value       = aws_lambda_function.this.function_name
}

output "function_arn" {
  description = "ARN of the pre-token-generation Lambda - wired into the tenant user pool's lambda_config"
  value       = aws_lambda_function.this.arn
}
