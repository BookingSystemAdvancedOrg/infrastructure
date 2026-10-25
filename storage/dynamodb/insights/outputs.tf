output "table_name" {
  description = "Name of the insights DynamoDB table"
  value       = aws_dynamodb_table.insights.name
}

output "table_arn" {
  description = "ARN of the insights DynamoDB table"
  value       = aws_dynamodb_table.insights.arn
}
