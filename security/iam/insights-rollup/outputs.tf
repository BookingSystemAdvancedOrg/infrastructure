output "role_arn" {
  description = "ARN of the insights-rollup Lambda's execution role"
  value       = aws_iam_role.this.arn
  sensitive   = true
}

output "role_name" {
  description = "Name of the insights-rollup Lambda's execution role"
  value       = aws_iam_role.this.name
}
