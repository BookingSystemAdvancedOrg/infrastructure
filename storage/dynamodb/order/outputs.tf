output "table_name" {
  description = "Name of the order DynamoDB table"
  value       = aws_dynamodb_table.order.name
}

output "table_arn" {
  description = "ARN of the order DynamoDB table"
  value       = aws_dynamodb_table.order.arn
}
