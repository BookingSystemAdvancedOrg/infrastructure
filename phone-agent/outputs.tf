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

output "call_alias_arn" {
  description = "phone-agent-call:live (the Connect test line's relay invokes it)"
  value       = aws_lambda_alias.live["phone-agent-call"].arn
}

output "table_name" {
  value = aws_dynamodb_table.this.name
}

output "recordings_bucket_name" {
  description = "Call recordings bucket (admin CSP media-src)"
  value       = aws_s3_bucket.recordings.bucket
}

# Dev twins: Booqy Console's seeder invokes this live alias as the twin's owner (dev only).
output "api_alias_arn" {
  value = aws_lambda_alias.live["phone-agent"].arn
}

# The voice gateway (dev A2A test, a2a-dev-test/) runs phone-agent-call's agent loop in a container:
# the same environment and the same access, without the provider and endpoint secrets it never reads.
output "gateway_access" {
  value = {
    environment = local.functions["phone-agent-call"].env
    statements  = [for s in local.statements["phone-agent-call"] : s if !contains(["ProviderSecrets", "EndpointKey"], s.Sid)]
  }
}
