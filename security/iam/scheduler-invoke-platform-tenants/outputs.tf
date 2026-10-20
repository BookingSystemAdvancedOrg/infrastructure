output "role_arn" {
  description = "ARN of the role EventBridge Scheduler assumes to invoke platform-tenants"
  value       = aws_iam_role.this.arn
  sensitive   = true
}

output "role_name" {
  description = "Name of the scheduler-invoke-platform-tenants role"
  value       = aws_iam_role.this.name
}
