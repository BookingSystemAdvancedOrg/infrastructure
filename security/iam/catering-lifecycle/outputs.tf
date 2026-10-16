output "role_arn" {
  description = "ARN of the CateringLifecycleFn Lambda's execution role — reference this in the Lambda's `role` argument"
  value       = aws_iam_role.this.arn
  sensitive   = true

  # Anything wiring this role into an event source mapping must wait for
  # the stream/queue permissions, or CreateEventSourceMapping fails its
  # permission check on first apply.
  depends_on = [aws_iam_role_policy.stream_read, aws_iam_role_policy.stream_dlq, aws_iam_role_policy.scheduled_invocation_dlq]
}

output "role_name" {
  description = "Name of the CateringLifecycleFn Lambda's execution role"
  value       = aws_iam_role.this.name
}
