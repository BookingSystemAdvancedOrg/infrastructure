output "bus_name" {
  description = "Name of the booqy-events bus (Lambda env EVENT_BUS_NAME)"
  value       = aws_cloudwatch_event_bus.this.name
}

output "bus_arn" {
  description = "ARN of the booqy-events bus (producer IAM and consumer rules)"
  value       = aws_cloudwatch_event_bus.this.arn
}
