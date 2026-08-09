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

variable "customer_bucket_arn" {
  description = "ARN of the customer front-end asset S3 bucket (storage/s3/customer-front-end-asset) this pipeline deploys to"
  type        = string
  sensitive   = false
}

variable "cloudfront_distribution_arn" {
  description = "ARN of the public CloudFront distribution (network/cloudfront/public) this pipeline invalidates after deploying"
  type        = string
  sensitive   = false
}
