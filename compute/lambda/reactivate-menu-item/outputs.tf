output "function_name" {
  description = "Name of the ReactivateMenuItemFn Lambda"
  value       = aws_lambda_function.this.function_name
}

output "function_arn" {
  description = "ARN of the ReactivateMenuItemFn Lambda"
  value       = aws_lambda_function.this.arn
}

output "invoke_arn" {
  description = "Invoke ARN of the ReactivateMenuItemFn Lambda — for wiring into the EventBridge Scheduler target that fires it when a menu item's inactive window ends"
  value       = aws_lambda_function.this.invoke_arn
}
