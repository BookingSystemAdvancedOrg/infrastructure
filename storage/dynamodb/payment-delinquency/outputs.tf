output "table_name" {
  description = "Name of the payment delinquency DynamoDB table"
  value       = aws_dynamodb_table.payment_delinquency.name
}

output "table_arn" {
  description = "ARN of the payment delinquency DynamoDB table"
  value       = aws_dynamodb_table.payment_delinquency.arn
}
