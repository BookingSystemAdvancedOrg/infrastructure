output "role_arn" {
  description = "ARN of the role EventBridge Scheduler assumes to invoke expire-layout-version — pass this as RoleArn in create_schedule calls"
  value       = aws_iam_role.this.arn
  sensitive   = true
}

output "role_name" {
  description = "Name of the scheduler-invoke-expire-layout-version role"
  value       = aws_iam_role.this.name
}
