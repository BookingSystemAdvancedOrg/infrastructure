output "table_name" {
  description = "Name of the catering menu DynamoDB table"
  value       = aws_dynamodb_table.catering_menu.name
}

output "table_arn" {
  description = "ARN of the catering menu DynamoDB table"
  value       = aws_dynamodb_table.catering_menu.arn
}
