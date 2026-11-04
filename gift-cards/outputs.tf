# Merged by the root config.tf (local.feature_wiring) into lambda releases,
# the tenant-context policy and the API Gateway integrations (CONTRACTS.md 12.2).
output "wiring" {
  value = {
    lambda_releases         = { (aws_lambda_function.fn.function_name) = { alias_name = aws_lambda_alias.live.name } }
    tenant_aware_role_names = { gift_cards = aws_iam_role.fn.name }
    staff_check_role_names  = { gift_cards = aws_iam_role.fn.name }
    api_integrations = {
      "gift-cards" = {
        function_name = aws_lambda_function.fn.function_name
        invoke_arn    = aws_lambda_alias.live.invoke_arn
      }
    }
  }
}
