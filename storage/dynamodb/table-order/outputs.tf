output "table_name" {
  description = "Name of the table-order DynamoDB table"
  value       = aws_dynamodb_table.table_order.name
}

output "table_arn" {
  description = "ARN of the table-order DynamoDB table"
  value       = aws_dynamodb_table.table_order.arn
}
