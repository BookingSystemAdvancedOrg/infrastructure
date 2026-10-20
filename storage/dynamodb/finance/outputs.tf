output "table_name" {
  description = "Name of the finance DynamoDB table"
  value       = aws_dynamodb_table.finance.name
}

output "table_arn" {
  description = "ARN of the finance DynamoDB table"
  value       = aws_dynamodb_table.finance.arn
}
