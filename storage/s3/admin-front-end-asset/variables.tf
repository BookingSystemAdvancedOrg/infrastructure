variable "environment" {
  description = "The environment to deploy to (dev or prod)"
  type        = string
  sensitive   = false
}

variable "cloudfront_distribution_arn" {
  description = "ARN of the private CloudFront distribution (network/cloudfront/private) - the only principal allowed to read this bucket"
  type        = string
  sensitive   = false
}
