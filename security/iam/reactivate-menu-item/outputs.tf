output "role_arn" {
  description = "ARN of the ReactivateMenuItemFn Lambda's execution role — reference this in the Lambda's `role` argument"
  value       = aws_iam_role.this.arn
  sensitive   = true

  # The function's async on-failure destination is validated against this
  # role when it's configured - the SQS permission must exist first.
  depends_on = [aws_iam_role_policy.scheduled_invocation_dlq]
}

output "role_name" {
  description = "Name of the ReactivateMenuItemFn Lambda's execution role"
  value       = aws_iam_role.this.name
}
