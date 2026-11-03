# Merged by the root config.tf (local.feature_wiring) into lambda releases,
# the tenant-context policy and the API Gateway integrations (CONTRACTS.md 12.2).
output "wiring" {
  value = {
    lambda_releases         = { for k, f in aws_lambda_function.fn : f.function_name => { alias_name = aws_lambda_alias.live[k].name } }
    tenant_aware_role_names = { site_builder = aws_iam_role.fn["site-builder"].name }
    staff_check_role_names  = {} # owner-only routes
    api_integrations = {
      "site-builder" = {
        function_name = aws_lambda_function.fn["site-builder"].function_name
        invoke_arn    = aws_lambda_alias.live["site-builder"].invoke_arn
      }
    }
  }
}

output "table_name" {
  description = "Site builder table name"
  value       = aws_dynamodb_table.this.name
}
