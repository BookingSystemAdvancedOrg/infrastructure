output "table_name" {
  description = "Name of the location DynamoDB table"
  value       = aws_dynamodb_table.location.name
}

output "table_arn" {
  description = "ARN of the location DynamoDB table"
  value       = aws_dynamodb_table.location.arn
}
