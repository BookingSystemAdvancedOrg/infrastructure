output "role_arn" {
  description = "ARN of the ReservationRemindersFn Lambda's execution role"
  value       = aws_iam_role.this.arn
  sensitive   = true
}

output "role_name" {
  description = "Name of the ReservationRemindersFn Lambda's execution role"
  value       = aws_iam_role.this.name
}
