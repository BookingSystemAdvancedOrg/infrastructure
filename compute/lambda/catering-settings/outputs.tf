output "function_name" {
  description = "Name of the catering-settings Lambda function"
  value       = aws_lambda_function.this.function_name
}

output "function_arn" {
  description = "ARN of the catering-settings Lambda function"
  value       = aws_lambda_function.this.arn
}

output "invoke_arn" {
  description = "Invoke ARN of the catering-settings Lambda — use this as the API Gateway integration URI"
  value       = aws_lambda_function.this.invoke_arn
}
