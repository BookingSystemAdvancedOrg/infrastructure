output "role_arn" {
  description = "ARN of the role EventBridge Scheduler assumes to invoke finance-rollup"
  value       = aws_iam_role.this.arn
  sensitive   = true
}

output "role_name" {
  description = "Name of the scheduler-invoke-finance-rollup role"
  value       = aws_iam_role.this.name
}
