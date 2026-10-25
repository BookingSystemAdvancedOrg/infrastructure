output "role_arn" {
  description = "ARN of the data-retention Lambda's execution role"
  value       = aws_iam_role.this.arn
  sensitive   = true
}

output "role_name" {
  description = "Name of the data-retention Lambda's execution role"
  value       = aws_iam_role.this.name
}

output "scheduler_role_arn" {
  description = "ARN of the role EventBridge Scheduler assumes to invoke data-retention"
  value       = aws_iam_role.scheduler.arn
  sensitive   = true
}
