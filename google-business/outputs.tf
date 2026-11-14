# Merged by the root config.tf (local.feature_wiring) into lambda releases,
# the tenant-context policy and the API Gateway integrations (CONTRACTS.md 12.2).
output "wiring" {
  value = {
    lambda_releases = { for k, f in aws_lambda_function.fn : f.function_name => { alias_name = aws_lambda_alias.live[k].name } }
    tenant_aware_role_names = {
      google_business      = aws_iam_role.fn["google-business"].name
      google_business_jobs = aws_iam_role.fn["google-business-jobs"].name
    }
    staff_check_role_names = {} # owner-only routes
    api_integrations = {
      "google-business" = {
        function_name = aws_lambda_function.fn["google-business"].function_name
        invoke_arn    = aws_lambda_alias.live["google-business"].invoke_arn
      }
    }
  }
}
