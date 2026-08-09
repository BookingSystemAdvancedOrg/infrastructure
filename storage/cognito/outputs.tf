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
