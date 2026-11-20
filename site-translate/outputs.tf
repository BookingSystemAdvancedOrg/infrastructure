# Merged by the root config.tf (local.feature_wiring) into lambda releases
# and the API Gateway integrations (CONTRACTS.md 12.2). Public route, no
# tenant JWT and no {locationId}: not in tenant_aware or staff_check roles
# (the function resolves the site itself from the trusted viewer host).
output "wiring" {
  value = {
    lambda_releases         = { (aws_lambda_function.fn.function_name) = { alias_name = aws_lambda_alias.live.name } }
    tenant_aware_role_names = {}
    staff_check_role_names  = {}
    api_integrations = {
      "site-translate" = {
        function_name = aws_lambda_function.fn.function_name
        invoke_arn    = aws_lambda_alias.live.invoke_arn
      }
    }
  }
}

output "table_name" {
  value = aws_dynamodb_table.cache.name
}

output "role_name" {
  value = aws_iam_role.fn.name
}
