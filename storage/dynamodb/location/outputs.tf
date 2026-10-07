output "table_name" {
  description = "Name of the location DynamoDB table"
  value       = aws_dynamodb_table.location.name
}

output "table_arn" {
  description = "ARN of the location DynamoDB table"
  value       = aws_dynamodb_table.location.arn
}

output "location_id_index_name" {
  description = "Name of the GSI that resolves a locationId to its tenant (and location settings)"
  value       = "byLocationId"
}
