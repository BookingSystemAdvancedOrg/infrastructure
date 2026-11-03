# Merged by the root config.tf (local.feature_wiring) into lambda releases,
# the tenant-context policy and the API Gateway integrations (CONTRACTS.md 12.2).
output "wiring" {
  value = {
    lambda_releases = { for k, f in aws_lambda_function.fn : f.function_name => { alias_name = aws_lambda_alias.live[k].name } }
    tenant_aware_role_names = {
      meta_ads      = aws_iam_role.fn["meta-ads"].name
      meta_ads_jobs = aws_iam_role.fn["meta-ads-jobs"].name
    }
    staff_check_role_names = {} # owner-only routes
    api_integrations = {
      "meta-ads" = {
        function_name = aws_lambda_function.fn["meta-ads"].function_name
        invoke_arn    = aws_lambda_alias.live["meta-ads"].invoke_arn
      }
    }
  }
}

# Read-only for social-posting (feature G, Run 2; OWNERSHIP.md A).
output "table_name" {
  description = "Meta ads table name"
  value       = aws_dynamodb_table.this.name
}

output "table_arn" {
  description = "Meta ads table ARN"
  value       = aws_dynamodb_table.this.arn
}

output "tenant_secret_prefix" {
  description = "Per-tenant Meta token secrets: <prefix><tenantId>"
  value       = local.tenant_secret_prefix
}
