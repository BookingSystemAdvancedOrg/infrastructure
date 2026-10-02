output "role_arn" {
  description = "ARN of the role EventBridge Scheduler assumes to invoke reactivate-menu-item — pass this as RoleArn in create_schedule/update_schedule calls"
  value       = aws_iam_role.this.arn
  sensitive   = true
}

output "role_name" {
  description = "Name of the scheduler-invoke-reactivate-menu-item role"
  value       = aws_iam_role.this.name
}
