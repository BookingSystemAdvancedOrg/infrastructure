variable "environment" {
  description = "The environment to deploy to (dev or prod)"
  type        = string
  sensitive   = false
}

variable "cloudfront_distribution_arn" {
  description = "ARN of the public CloudFront distribution (network/cloudfront/public) - the only principal allowed to read this bucket"
  type        = string
  sensitive   = false
}
