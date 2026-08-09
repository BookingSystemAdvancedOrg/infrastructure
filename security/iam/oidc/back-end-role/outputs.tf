output "role_arn" {
  description = "ARN of the backend deploy role - set as the role-to-assume in the backend repo's GitHub Actions workflow"
  value       = aws_iam_role.this.arn
  sensitive   = true
}

output "role_name" {
  description = "Name of the backend deploy role"
  value       = aws_iam_role.this.name
}
