output "role_arn" {
  description = "ARN of the customer front-end deploy role - set as the role-to-assume in the customer front-end repo's GitHub Actions workflow"
  value       = aws_iam_role.this.arn
  sensitive   = true
}

output "role_name" {
  description = "Name of the customer front-end deploy role"
  value       = aws_iam_role.this.name
}
