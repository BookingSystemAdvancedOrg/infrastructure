output "role_arn" {
  description = "ARN of the role EventBridge Scheduler assumes to invoke catering-lifecycle — pass this as RoleArn in create_schedule calls"
  value       = aws_iam_role.this.arn
  sensitive   = true
}

output "role_name" {
  description = "Name of the scheduler-invoke-catering-lifecycle role"
  value       = aws_iam_role.this.name
}

output "schedule_group_name" {
  description = "Name of the EventBridge Scheduler group every catering schedule is created in"
  value       = aws_scheduler_schedule_group.catering.name
}
