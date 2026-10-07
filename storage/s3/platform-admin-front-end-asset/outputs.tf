output "bucket_name" {
  description = "Name of the platform admin (operator app) front-end asset S3 bucket"
  value       = aws_s3_bucket.platform_admin_front_end_asset.id
}

output "bucket_arn" {
  description = "ARN of the platform admin front-end asset S3 bucket"
  value       = aws_s3_bucket.platform_admin_front_end_asset.arn
}

output "bucket_regional_domain_name" {
  description = "Regional domain name - for wiring this bucket as the platform-admin CloudFront distribution's origin"
  value       = aws_s3_bucket.platform_admin_front_end_asset.bucket_regional_domain_name
}
