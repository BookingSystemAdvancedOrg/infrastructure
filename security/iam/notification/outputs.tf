output "role_arn" {
  description = "ARN of the NotificationFn Lambda's execution role — reference this in the Lambda's `role` argument"
  value       = aws_iam_role.this.arn
  sensitive   = true

  # The event source mappings validate their on-failure destination
  # against this role - make sure the SQS permission exists first.
  depends_on = [aws_iam_role_policy.stream_dlq]
}

output "role_name" {
  description = "Name of the NotificationFn Lambda's execution role"
  value       = aws_iam_role.this.name
}
