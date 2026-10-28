output "bucket_name" {
  description = "Sites bucket (sites/<tenantId>/)"
  value       = aws_s3_bucket.sites.bucket
}

output "bucket_regional_domain_name" {
  description = "Sites bucket regional domain (multi-tenant distribution origin)"
  value       = aws_s3_bucket.sites.bucket_regional_domain_name
}

output "deploy_boundary_arn" {
  description = "Permissions boundary of every per-site deploy role"
  value       = aws_iam_policy.deploy_boundary.arn
}

output "function_name" {
  description = "site-repo function name"
  value       = aws_lambda_function.fn.function_name
}

output "alias_name" {
  description = "Live alias name"
  value       = aws_lambda_alias.live.name
}

output "alias_arn" {
  description = "Live alias ARN (invoked by onboarding, offboarding and platform-tenants)"
  value       = aws_lambda_alias.live.arn
}

output "enabled" {
  description = "Whether site repos are on (the GitHub App secret is configured)"
  value       = local.enabled
}
