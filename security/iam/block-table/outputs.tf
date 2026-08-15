output "role_arn" {
  description = "ARN of the BlockTableFn Lambda's execution role — reference this in the Lambda's `role` argument"
  value       = aws_iam_role.this.arn
  sensitive   = true
}

output "role_name" {
  description = "Name of the BlockTableFn Lambda's execution role"
  value       = aws_iam_role.this.name
}
