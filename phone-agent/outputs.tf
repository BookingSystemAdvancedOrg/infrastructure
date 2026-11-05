# Merged by the root config.tf (local.feature_wiring) into lambda releases,
# the tenant-context policy and the API Gateway integrations (CONTRACTS.md 12.2).
output "wiring" {
  value = {
    lambda_releases = { for k, f in aws_lambda_function.fn : f.function_name => { alias_name = aws_lambda_alias.live[k].name } }
    tenant_aware_role_names = {
      phone_agent      = aws_iam_role.fn["phone-agent"].name
      phone_agent_call = aws_iam_role.fn["phone-agent-call"].name
      phone_agent_jobs = aws_iam_role.fn["phone-agent-jobs"].name
    }
    staff_check_role_names = { phone_agent = aws_iam_role.fn["phone-agent"].name }
    api_integrations = {
      "phone-agent" = {
        function_name = aws_lambda_function.fn["phone-agent"].function_name
        invoke_arn    = aws_lambda_alias.live["phone-agent"].invoke_arn
      }
    }
  }
}

output "turn_endpoint_url" {
  description = "The agent turn endpoint (Function URL) to set in the voice provider's custom LLM settings"
  value       = aws_lambda_function_url.turn.function_url
}
