output "distribution_id" {
  description = "ID of the private CloudFront distribution"
  value       = aws_cloudfront_distribution.this.id
}

output "distribution_arn" {
  description = "ARN of the private CloudFront distribution - wire this into admin-front-end-asset's and menu-image's bucket policies as an allowed AWS:SourceArn"
  value       = aws_cloudfront_distribution.this.arn
}

output "distribution_domain_name" {
  description = "Default *.cloudfront.net domain the admin front-end is reachable at until a custom domain is wired up"
  value       = aws_cloudfront_distribution.this.domain_name
}
