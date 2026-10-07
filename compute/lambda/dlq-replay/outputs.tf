output "function_name" {
  description = "Name of the DlqReplayFn Lambda"
  value       = aws_lambda_function.this.function_name
}

output "function_arn" {
  description = "ARN of the DlqReplayFn Lambda"
  value       = aws_lambda_function.this.arn
}

output "invoke_arn" {
  description = "Invoke ARN of the DlqReplayFn Lambda — for wiring into API Gateway"
  value       = aws_lambda_function.this.invoke_arn
}

output "schedule_name" {
  description = "Name of the recurring EventBridge schedule that runs the replay"
  value       = aws_scheduler_schedule.replay.name
}
