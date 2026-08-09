output "table_name" {
  description = "Name of the menu DynamoDB table"
  value       = aws_dynamodb_table.menu.name
}

output "table_arn" {
  description = "ARN of the menu DynamoDB table"
  value       = aws_dynamodb_table.menu.arn
}
