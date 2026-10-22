output "role_arn" {
  description = "ARN of the guest-privacy Lambda's execution role"
  value       = aws_iam_role.this.arn
  sensitive   = true
}

output "role_name" {
  description = "Name of the guest-privacy Lambda's execution role"
  value       = aws_iam_role.this.name
}
