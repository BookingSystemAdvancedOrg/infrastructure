variable "environment" {
  description = "The environment to deploy to (dev or prod)"
  type        = string
}

variable "region" {
  description = "AWS region"
  type        = string
}

variable "ecr_repository_url" {
  description = "ECR repository URL of the site-repo function"
  type        = string
  sensitive   = true
}

variable "tenant_table_name" {
  description = "Tenant table (PROFILE and SITE rows)"
  type        = string
}

variable "tenant_table_arn" {
  description = "Tenant table ARN"
  type        = string
}

variable "distribution_arn" {
  description = "Multi-tenant distribution that serves sites/<tenantId>/ (empty: none yet)"
  type        = string
  default     = ""
}

variable "oidc_provider_arn" {
  description = "The account's existing GitHub Actions OIDC provider, trusted by every per-site deploy role"
  type        = string
}

variable "github_org" {
  description = "GitHub organisation of the site repos"
  type        = string
}

variable "github_app_secret_name" {
  description = "Secrets Manager secret with the \"Booqy Sites\" GitHub App key, JSON {\"app_id\", \"private_key\"}. Created by hand. Empty: no site repos (the onboarding step is skipped)."
  type        = string
}

variable "template_repo" {
  description = "Template repo every site repo is created from"
  type        = string
}


variable "api_base_url" {
  description = "Public API base URL written to booqy.json"
  type        = string
}

variable "menu_image_base_url" {
  description = "Menu image base URL written to booqy.json"
  type        = string
}

variable "preview_domain" {
  description = "Platform domain of the <slug>.<domain> preview (empty: no preview hostname)"
  type        = string
}

variable "stripe_publishable_key" {
  description = "Stripe publishable key (public) written to booqy.json"
  type        = string
}

variable "turnstile_site_key" {
  description = "Turnstile site key (public) written to booqy.json"
  type        = string
}

variable "alert_topic_arn" {
  description = "Operator alerts"
  type        = string
}

variable "link_prod_account_id" {
  description = "Dev only: the prod account whose site-repo role may assume booqy-sites-prod-link. Empty: no link role."
  type        = string
  default     = ""
}

variable "link_dev_account_id" {
  description = "Prod only: the dev account whose booqy-sites-prod-link role prod's site-repo assumes. Empty: no dev side."
  type        = string
  default     = ""
}

variable "platform_tenants_alias_arn" {
  description = "This account's platform-tenants live alias (the only thing the link role may invoke)"
  type        = string
  default     = ""
}
