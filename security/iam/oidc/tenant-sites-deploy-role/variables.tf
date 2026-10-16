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

variable "github_org" {
  description = "GitHub organization the tenant website repos live in"
  type        = string
  sensitive   = false
}

variable "site_repo_pattern" {
  description = "Repo-name pattern (IAM StringLike) of tenant website repos allowed to deploy, e.g. site-*"
  type        = string
  sensitive   = false
}

variable "sites_bucket_arn" {
  description = "ARN of the tenant-sites bucket (network/platform-domain)"
  type        = string
  sensitive   = false
}
