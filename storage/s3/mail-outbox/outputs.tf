output "bucket_name" {
  description = "Name of the dev mail outbox bucket"
  value       = aws_s3_bucket.mail_outbox.id
}

output "bucket_arn" {
  description = "ARN of the dev mail outbox bucket"
  value       = aws_s3_bucket.mail_outbox.arn
}
