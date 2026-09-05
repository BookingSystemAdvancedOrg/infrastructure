output "table_name" {
  description = "Name of the order DynamoDB table"
  value       = aws_dynamodb_table.order.name
}

output "table_arn" {
  description = "ARN of the order DynamoDB table"
  value       = aws_dynamodb_table.order.arn
}

output "stream_arn" {
  description = "ARN of the order table's DynamoDB Stream — granted read-only to the notification Lambda's role"
  value       = aws_dynamodb_table.order.stream_arn
}
