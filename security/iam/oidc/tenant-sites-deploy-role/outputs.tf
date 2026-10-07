output "role_arn" {
  description = "ARN of the tenant-sites deploy role - role-to-assume in every tenant website repo's deploy workflow"
  value       = aws_iam_role.this.arn
}
