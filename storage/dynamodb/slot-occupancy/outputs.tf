output "table_name" {
  description = "Name of the slot occupancy DynamoDB table"
  value       = aws_dynamodb_table.slot_occupancy.name
}

output "table_arn" {
  description = "ARN of the slot occupancy DynamoDB table"
  value       = aws_dynamodb_table.slot_occupancy.arn
}
