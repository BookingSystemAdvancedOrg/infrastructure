output "user_pool_id" {
  description = "ID of the tenant (owner/staff) Cognito User Pool"
  value       = aws_cognito_user_pool.this.id
}

output "user_pool_arn" {
  description = "ARN of the tenant Cognito User Pool"
  value       = aws_cognito_user_pool.this.arn
}

output "user_pool_client_id" {
  description = "ID of the app client used for owner/staff login (through manage-auth)"
  value       = aws_cognito_user_pool_client.this.id
}

output "user_pool_client_secret" {
  description = "Secret of the app client used for owner/staff login"
  value       = aws_cognito_user_pool_client.this.client_secret
  sensitive   = true
}

output "owner_group_name" {
  description = "Name of the Cognito group for restaurant owners"
  value       = aws_cognito_user_group.owner_user.name
}

output "staff_group_name" {
  description = "Name of the Cognito group for restaurant staff"
  value       = aws_cognito_user_group.staff_user.name
}
