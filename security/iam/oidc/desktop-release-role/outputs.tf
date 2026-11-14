output "role_arn" {
  description = "ARN the desktop installer workflow assumes"
  value       = aws_iam_role.this.arn
}
