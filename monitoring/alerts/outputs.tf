output "topic_arn" {
  description = "ARN of the platform alerts SNS topic"
  value       = aws_sns_topic.alerts.arn
}
