output "topic_arn" {
  description = "ARN of the platform alerts SNS topic"
  value       = aws_sns_topic.alerts.arn
}

output "us_east_1_topic_arn" {
  description = "ARN of the us-east-1 twin of the alerts topic (CloudFront alarms publish here)"
  value       = aws_sns_topic.alerts_us_east_1.arn
}

output "uptime_checks" {
  description = "What the uptime check loads every 5 minutes: name => url and the expected status (also what the pipelines' smoke tests check)"
  value       = { for name, c in local.uptime_checks : name => { url = c.url, expect_status = c.expect_status } }
}
