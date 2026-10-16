output "lifecycle_stream_dlq_arn" {
  description = "ARN of the DLQ for catering-requests stream batches catering-lifecycle failed to process"
  value       = aws_sqs_queue.this["lifecycle_stream"].arn
}

output "notification_stream_dlq_arn" {
  description = "ARN of the DLQ for stream batches NotificationFn failed to process (reservation, order and catering-requests streams)"
  value       = aws_sqs_queue.this["notification_stream"].arn
}

output "scheduled_invocation_dlq_arn" {
  description = "ARN of the DLQ for failed scheduled (asynchronous) Lambda invocations - the on-failure destination of every scheduler-invoked function"
  value       = aws_sqs_queue.this["scheduled_invocation"].arn
}

# URLs, names and ARNs by key, for the replay Lambda (SQS API calls take the
# URL), the CloudWatch alarms (QueueName dimension) and IAM policies.
output "queue_urls" {
  description = "Map of DLQ key (lifecycle_stream, notification_stream, scheduled_invocation) to queue URL"
  value       = { for k, q in aws_sqs_queue.this : k => q.url }
}

output "queue_names" {
  description = "Map of DLQ key (lifecycle_stream, notification_stream, scheduled_invocation) to queue name"
  value       = { for k, q in aws_sqs_queue.this : k => q.name }
}

output "queue_arns" {
  description = "Map of DLQ key (lifecycle_stream, notification_stream, scheduled_invocation) to queue ARN"
  value       = { for k, q in aws_sqs_queue.this : k => q.arn }
}
