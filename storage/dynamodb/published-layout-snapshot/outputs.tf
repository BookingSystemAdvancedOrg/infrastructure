output "table_name" {
  description = "Name of the published layout snapshot DynamoDB table"
  value       = aws_dynamodb_table.published_layout_snapshot.name
}

output "table_arn" {
  description = "ARN of the published layout snapshot DynamoDB table"
  value       = aws_dynamodb_table.published_layout_snapshot.arn
}
