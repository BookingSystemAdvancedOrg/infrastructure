output "table_name" {
  description = "Name of the live layout element DynamoDB table"
  value       = aws_dynamodb_table.live_layout_element.name
}

output "table_arn" {
  description = "ARN of the live layout element DynamoDB table"
  value       = aws_dynamodb_table.live_layout_element.arn
}
