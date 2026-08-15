variable "environment" {
  description = "The environment to deploy to (dev or prod)"
  type        = string
  sensitive   = false
}

variable "public_cloudfront_distribution_arn" {
  description = "ARN of the public CloudFront distribution (network/cloudfront/public) - allowed to read this bucket to show menu images to customers"
  type        = string
  sensitive   = false
}

variable "private_cloudfront_distribution_arn" {
  description = "ARN of the private CloudFront distribution (network/cloudfront/private) - allowed to read this bucket to show menu images while staff edit the menu"
  type        = string
  sensitive   = false
}
