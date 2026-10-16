output "function_name" {
  description = "Name of the ReservationRemindersFn Lambda"
  value       = aws_lambda_function.this.function_name
}

output "function_arn" {
  description = "ARN of the ReservationRemindersFn Lambda"
  value       = aws_lambda_function.this.arn
}

output "alias_name" {
  description = "Name of the alias every caller invokes"
  value       = aws_lambda_alias.live.name
}

output "alias_arn" {
  description = "Qualified ARN of the live alias - use this (not function_arn) as an invoke / event source / Scheduler target"
  value       = aws_lambda_alias.live.arn
}
