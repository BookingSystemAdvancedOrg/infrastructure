output "function_name" {
  description = "Name of the custom message Lambda - for the user pool's invoke permission"
  value       = aws_lambda_function.this.function_name
}

output "alias_name" {
  description = "Name of the alias Cognito invokes"
  value       = aws_lambda_alias.live.name
}

output "alias_arn" {
  description = "Qualified ARN of the live alias - the user pool's lambda_config custom_message"
  value       = aws_lambda_alias.live.arn
}
