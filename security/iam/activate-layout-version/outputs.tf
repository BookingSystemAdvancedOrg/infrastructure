output "role_arn" {
  description = "ARN of the ActivateLayoutVersionFn Lambda's execution role - reference this in the Lambda's `role` argument"
  value       = aws_iam_role.this.arn
  sensitive   = true
}

output "role_name" {
  description = "Name of the ActivateLayoutVersionFn Lambda's execution role"
  value       = aws_iam_role.this.name
}

# The function gets RESERVATION_TABLE_NAME only after the Query grant is in
# place: with the name and no grant, activation answers 503.
output "reservation_table_name" {
  description = "Reservation table name, available once the Query grant exists"
  value       = var.reservation_table_name
  depends_on  = [aws_iam_role_policy.reservation_query]
}
