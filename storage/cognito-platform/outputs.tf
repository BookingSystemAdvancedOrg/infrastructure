output "user_pool_id" {
  description = "ID of the platform operator Cognito User Pool"
  value       = aws_cognito_user_pool.this.id
}

output "user_pool_arn" {
  description = "ARN of the platform operator Cognito User Pool"
  value       = aws_cognito_user_pool.this.arn
}

output "client_id" {
  description = "App client ID the platform admin app signs in with (hosted login, code + PKCE)"
  value       = aws_cognito_user_pool_client.platform_admin.id
}

output "hosted_login_url" {
  description = "Base URL of the operator pool's hosted login (OAuth authorize/token endpoints live under it)"
  value       = "https://${aws_cognito_user_pool_domain.this.domain}.auth.${data.aws_region.current.region}.amazoncognito.com"
}

output "admin_scope" {
  description = "OAuth scope every /platform/* route requires"
  value       = tolist(aws_cognito_resource_server.platform.scope_identifiers)[0]
}
