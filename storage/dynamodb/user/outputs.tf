output "table_name" {
  description = "Name of the users DynamoDB table"
  value       = aws_dynamodb_table.user.name
}

output "table_arn" {
  description = "ARN of the users DynamoDB table"
  value       = aws_dynamodb_table.user.arn
}

output "tenant_index_name" {
  description = "Name of the GSI that lists a tenant's users (tenantId -> USER#<sub>)"
  value       = "byTenant"
}
