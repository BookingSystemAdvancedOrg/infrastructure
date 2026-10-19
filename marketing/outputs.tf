output "function_names" {
  description = "Function name per marketing function"
  value       = { for k, f in aws_lambda_function.fn : k => f.function_name }
}

output "alias_names" {
  description = "Live alias name per function"
  value       = { for k, a in aws_lambda_alias.live : k => a.name }
}

output "alias_invoke_arns" {
  description = "Live alias invoke ARN per function (API Gateway integrations)"
  value       = { for k, a in aws_lambda_alias.live : k => a.invoke_arn }
}

output "role_names" {
  description = "Execution role name per function"
  value       = { for k, r in aws_iam_role.fn : k => r.name }
}

output "table_name" {
  description = "Marketing table name"
  value       = aws_dynamodb_table.marketing.name
}
