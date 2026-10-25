output "function_name" {
  description = "kassa function name"
  value       = aws_lambda_function.fn.function_name
}

output "alias_name" {
  description = "Live alias name"
  value       = aws_lambda_alias.live.name
}

output "alias_invoke_arn" {
  description = "Live alias invoke ARN (API Gateway integration)"
  value       = aws_lambda_alias.live.invoke_arn
}

output "role_name" {
  description = "Execution role name"
  value       = aws_iam_role.fn.name
}

output "journal_table_name" {
  description = "The append-only journal table"
  value       = aws_dynamodb_table.journal.name
}

output "table_name" {
  description = "The kassa table (registers, bills, receipt pointers)"
  value       = aws_dynamodb_table.kassa.name
}

output "table_arn" {
  description = "The kassa table ARN"
  value       = aws_dynamodb_table.kassa.arn
}

output "journal_table_arn" {
  description = "The append-only journal table ARN"
  value       = aws_dynamodb_table.journal.arn
}
