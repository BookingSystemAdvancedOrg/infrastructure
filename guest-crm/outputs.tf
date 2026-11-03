# Merged by the root config.tf (local.feature_wiring) into lambda releases,
# the tenant-context policy and the API Gateway integrations (CONTRACTS.md 12.2).
output "wiring" {
  value = {
    lambda_releases = { for k, f in aws_lambda_function.fn : f.function_name => { alias_name = aws_lambda_alias.live[k].name } }
    tenant_aware_role_names = {
      guest_crm      = aws_iam_role.fn["guest-crm"].name
      guest_crm_sync = aws_iam_role.fn["guest-crm-sync"].name
    }
    staff_check_role_names = { guest_crm = aws_iam_role.fn["guest-crm"].name }
    api_integrations = {
      "guest-crm" = {
        function_name = aws_lambda_function.fn["guest-crm"].function_name
        invoke_arn    = aws_lambda_alias.live["guest-crm"].invoke_arn
      }
    }
  }
}

output "table_name" {
  description = "Guest CRM table name"
  value       = aws_dynamodb_table.this.name
}
