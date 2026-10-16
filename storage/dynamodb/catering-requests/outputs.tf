output "table_name" {
  description = "Name of the catering requests DynamoDB table"
  value       = aws_dynamodb_table.catering_requests.name
}

output "table_arn" {
  description = "ARN of the catering requests DynamoDB table"
  value       = aws_dynamodb_table.catering_requests.arn
}

output "stream_arn" {
  description = "ARN of the catering requests table's DynamoDB Stream — for granting stream-read access to NotificationFn and catering-lifecycle"
  value       = aws_dynamodb_table.catering_requests.stream_arn
}
