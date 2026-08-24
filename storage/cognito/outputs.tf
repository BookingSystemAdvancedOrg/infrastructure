output "user_pool_id" {
  description = "ID of the staff/owner/super-admin Cognito User Pool"
  value       = aws_cognito_user_pool.this.id
}

output "user_pool_arn" {
  description = "ARN of the Cognito User Pool"
  value       = aws_cognito_user_pool.this.arn
}

output "user_pool_client_id" {
  description = "ID of the app client used for staff/owner/super-user login"
  value       = aws_cognito_user_pool_client.this.id
}

output "user_pool_client_secret" {
  description = "Secret of the app client used for staff/owner/super-user login"
  value       = aws_cognito_user_pool_client.this.client_secret
  sensitive   = true
}

output "super_admin_temp_password" {
  description = "Shared temporary password (FORCE_CHANGE_PASSWORD) for every bootstrap super_user in super_admin_emails. Same value for everyone - each person should log in and rotate to their own password promptly, since this value is a fixed non-secret default until you override it."
  value       = var.super_admin_temp_password
  sensitive   = true
}
