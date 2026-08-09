output "bucket_name" {
  description = "Name of the menu images S3 bucket"
  value       = aws_s3_bucket.menu_image.id
}

output "bucket_arn" {
  description = "ARN of the menu images S3 bucket"
  value       = aws_s3_bucket.menu_image.arn
}

output "bucket_regional_domain_name" {
  description = "Regional domain name - for wiring this bucket as a CloudFront origin"
  value       = aws_s3_bucket.menu_image.bucket_regional_domain_name
}
