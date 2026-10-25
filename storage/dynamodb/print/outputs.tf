output "table_name" {
  description = "Name of the print DynamoDB table"
  value       = aws_dynamodb_table.print.name
}

output "table_arn" {
  description = "ARN of the print DynamoDB table"
  value       = aws_dynamodb_table.print.arn
}
