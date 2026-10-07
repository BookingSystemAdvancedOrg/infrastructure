output "table_name" {
  description = "Name of the catering request history DynamoDB table"
  value       = aws_dynamodb_table.catering_request_history.name
}

output "table_arn" {
  description = "ARN of the catering request history DynamoDB table"
  value       = aws_dynamodb_table.catering_request_history.arn
}
