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
  description = "GitHub repo this role trusts, as \"org@*/repo-name\" - used in the trust policy's sub claim condition"
  type        = string
  sensitive   = false
}

variable "website_bucket_arn" {
  description = "ARN of the public page bucket (network/platform-domain landing) this pipeline deploys to"
  type        = string
  sensitive   = false
}

variable "cloudfront_distribution_arn" {
  description = "ARN of the public page CloudFront distribution this pipeline invalidates after deploying"
  type        = string
  sensitive   = false
}
