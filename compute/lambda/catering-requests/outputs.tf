output "function_name" {
  description = "Name of the catering-requests Lambda function"
  value       = aws_lambda_function.this.function_name
}

output "function_arn" {
  description = "ARN of the catering-requests Lambda function"
  value       = aws_lambda_function.this.arn
}

output "invoke_arn" {
  description = "Invoke ARN of the catering-requests Lambda — use this as the API Gateway integration URI"
  value       = aws_lambda_function.this.invoke_arn
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
