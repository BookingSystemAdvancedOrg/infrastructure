output "distribution_id" {
  description = "ID of the platform admin CloudFront distribution"
  value       = aws_cloudfront_distribution.this.id
}

output "distribution_arn" {
  description = "ARN of the platform admin CloudFront distribution"
  value       = aws_cloudfront_distribution.this.arn
}

output "distribution_domain_name" {
  description = "*.cloudfront.net domain of the platform admin app (until ops.<platform domain> exists)"
  value       = aws_cloudfront_distribution.this.domain_name
}
