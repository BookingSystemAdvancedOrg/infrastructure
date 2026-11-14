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

variable "github_repos" {
  description = "GitHub repos this role trusts, each as \"org@*/repo-name\" (sub claim condition)"
  type        = list(string)
  sensitive   = false
}

variable "downloads_bucket_arn" {
  description = "ARN of the desktop installer bucket (network/platform-domain downloads.tf)"
  type        = string
  sensitive   = false
}
