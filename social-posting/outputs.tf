# Merged by the root config.tf (local.feature_wiring) into lambda releases,
# the tenant-context policy and the API Gateway integrations (CONTRACTS.md 12.2).
output "wiring" {
  value = {
    lambda_releases         = { (aws_lambda_function.fn.function_name) = { alias_name = aws_lambda_alias.live.name } }
    tenant_aware_role_names = { social_posting = aws_iam_role.fn.name }
    staff_check_role_names  = {} # owner-only routes
    api_integrations = {
      "social-posting" = {
        function_name = aws_lambda_function.fn.function_name
        invoke_arn    = aws_lambda_alias.live.invoke_arn
      }
    }
  }
}
