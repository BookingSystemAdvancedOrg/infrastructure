output "bucket_name" {
  description = "Name of the admin front-end asset S3 bucket"
  value       = aws_s3_bucket.admin_front_end_asset.id
}

output "bucket_arn" {
  description = "ARN of the admin front-end asset S3 bucket"
  value       = aws_s3_bucket.admin_front_end_asset.arn
}

output "bucket_regional_domain_name" {
  description = "Regional domain name - for wiring this bucket as the private CloudFront distribution's origin"
  value       = aws_s3_bucket.admin_front_end_asset.bucket_regional_domain_name
}
