output "bucket_name" {
  description = "Name of the catering documents archive bucket"
  value       = aws_s3_bucket.catering_documents.bucket
}

output "bucket_arn" {
  description = "ARN of the catering documents archive bucket"
  value       = aws_s3_bucket.catering_documents.arn
}
