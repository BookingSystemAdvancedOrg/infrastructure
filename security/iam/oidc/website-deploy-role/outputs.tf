output "role_arn" {
  description = "ARN of the booqy-website deploy role - role-to-assume in that repo's GitHub Actions workflow"
  value       = aws_iam_role.this.arn
}

output "role_name" {
  description = "Name of the booqy-website deploy role"
  value       = aws_iam_role.this.name
}
