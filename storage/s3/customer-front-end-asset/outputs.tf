output "bucket_name" {
  description = "Name of the customer front-end asset S3 bucket"
  value       = aws_s3_bucket.customer_front_end_asset.id
}

output "bucket_arn" {
  description = "ARN of the customer front-end asset S3 bucket"
  value       = aws_s3_bucket.customer_front_end_asset.arn
}

output "bucket_regional_domain_name" {
  description = "Regional domain name - for wiring this bucket as the public CloudFront distribution's origin"
  value       = aws_s3_bucket.customer_front_end_asset.bucket_regional_domain_name
}
