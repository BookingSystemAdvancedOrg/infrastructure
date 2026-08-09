output "function_name" {
  description = "Name of the GetReservationFn Lambda"
  value       = aws_lambda_function.this.function_name
}

output "function_arn" {
  description = "ARN of the GetReservationFn Lambda"
  value       = aws_lambda_function.this.arn
}

output "invoke_arn" {
  description = "Invoke ARN of the GetReservationFn Lambda — for wiring into API Gateway or a Function URL later"
  value       = aws_lambda_function.this.invoke_arn
}
