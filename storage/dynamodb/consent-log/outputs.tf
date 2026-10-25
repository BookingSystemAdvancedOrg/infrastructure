output "table_name" {
  description = "Name of the consent log table"
  value       = aws_dynamodb_table.consent_log.name
}

output "table_arn" {
  description = "ARN of the consent log table"
  value       = aws_dynamodb_table.consent_log.arn
}

output "tenant_index_name" {
  description = "GSI listing one restaurant's consent records (tenantId, at)"
  value       = "byTenant"
}
