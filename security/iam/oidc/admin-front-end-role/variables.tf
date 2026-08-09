variable "environment" {
  description = "The environment to deploy to (dev or prod)"
  type        = string
  sensitive   = false
}

variable "oidc_provider_arn" {
  description = "ARN of the GitHub Actions OIDC provider (security/iam/oidc/provider)"
  type        = string
  sensitive   = false
}

variable "github_repo" {
  description = "GitHub repo this role trusts, as \"org/repo-name\" - used in the trust policy's sub claim condition"
  type        = string
  sensitive   = false
}

variable "admin_bucket_arn" {
  description = "ARN of the admin front-end asset S3 bucket (storage/s3/admin-front-end-asset) this pipeline deploys to"
  type        = string
  sensitive   = false
}

variable "cloudfront_distribution_arn" {
  description = "ARN of the private CloudFront distribution (network/cloudfront/private) this pipeline invalidates after deploying"
  type        = string
  sensitive   = false
}
