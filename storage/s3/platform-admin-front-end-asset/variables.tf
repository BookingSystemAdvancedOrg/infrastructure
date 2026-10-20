variable "environment" {
  description = "The environment to deploy to (dev or prod)"
  type        = string
  sensitive   = false
}

variable "cloudfront_distribution_arn" {
  description = "ARN of the platform-admin CloudFront distribution (network/cloudfront/platform-admin) - the only principal allowed to read this bucket"
  type        = string
  sensitive   = false
}

variable "noncurrent_version_days" {
  description = "Days a previous build's files stay as noncurrent versions after a deploy replaced or deleted them - the window in which a redeploy of an older commit is a no-risk rollback"
  type        = number
  sensitive   = false
  default     = 30
}
