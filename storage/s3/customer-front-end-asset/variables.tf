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

variable "additional_cloudfront_distribution_arns" {
  description = "Further CloudFront distributions allowed to read the site through OAC (the restaurant-domain multi-tenant distribution when tenant sites are on)"
  type        = list(string)
  sensitive   = false
  default     = []
}

variable "noncurrent_version_days" {
  description = "Days a previous build's files stay as noncurrent versions after a deploy replaced or deleted them - the window in which a redeploy of an older commit is a no-risk rollback"
  type        = number
  sensitive   = false
  default     = 30
}
