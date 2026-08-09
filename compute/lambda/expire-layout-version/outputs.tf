output "function_name" {
  description = "Name of the ExpireLayoutVersionFn Lambda"
  value       = aws_lambda_function.this.function_name
}

output "function_arn" {
  description = "ARN of the ExpireLayoutVersionFn Lambda"
  value       = aws_lambda_function.this.arn
}

output "invoke_arn" {
  description = "Invoke ARN of the ExpireLayoutVersionFn Lambda — for wiring into the EventBridge Scheduler target that fires it at cutover"
  value       = aws_lambda_function.this.invoke_arn
}
