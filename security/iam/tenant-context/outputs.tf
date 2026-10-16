output "policy_arn" {
  description = "ARN of the shared tenant-context read policy"
  value       = aws_iam_policy.this.arn
}
