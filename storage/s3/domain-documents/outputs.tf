output "bucket_name" {
  description = "Name of the domain documents (registreringsbevis) bucket"
  value       = aws_s3_bucket.this.id
}

output "bucket_arn" {
  description = "ARN of the domain documents bucket"
  value       = aws_s3_bucket.this.arn
}
