output "table_name" {
  description = "Name of the catering discount tiers DynamoDB table"
  value       = aws_dynamodb_table.catering_discount_tiers.name
}

output "table_arn" {
  description = "ARN of the catering discount tiers DynamoDB table"
  value       = aws_dynamodb_table.catering_discount_tiers.arn
}
