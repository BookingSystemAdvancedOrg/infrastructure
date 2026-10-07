output "table_name" {
  description = "Name of the tenant DynamoDB table"
  value       = aws_dynamodb_table.tenant.name
}

output "table_arn" {
  description = "ARN of the tenant DynamoDB table"
  value       = aws_dynamodb_table.tenant.arn
}
