output "table_name" {
  description = "Name of the reservation DynamoDB table"
  value       = aws_dynamodb_table.reservation.name
}

output "table_arn" {
  description = "ARN of the reservation DynamoDB table"
  value       = aws_dynamodb_table.reservation.arn
}

output "stream_arn" {
  description = "ARN of the reservation table's DynamoDB Stream — for granting stream-read access to NotificationFn"
  value       = aws_dynamodb_table.reservation.stream_arn
}
