output "table_name" {
  description = "Name of the catering requests DynamoDB table"
  value       = aws_dynamodb_table.catering_requests.name
}

output "table_arn" {
  description = "ARN of the catering requests DynamoDB table"
  value       = aws_dynamodb_table.catering_requests.arn
}
