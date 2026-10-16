output "table_name" {
  description = "Name of the request guard DynamoDB table"
  value       = aws_dynamodb_table.request_guard.name
}

output "table_arn" {
  description = "ARN of the request guard DynamoDB table"
  value       = aws_dynamodb_table.request_guard.arn
}
