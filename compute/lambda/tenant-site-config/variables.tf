variable "environment" {
  description = "The environment to deploy to (dev or prod)"
  type        = string
  sensitive   = false
}

variable "role_arn" {
  description = "ARN of the TenantSiteConfigFn execution role (security/iam/tenant-site-config)"
  type        = string
  sensitive   = true
}

variable "ecr_repository_url" {
  description = "Repository URL of the TenantSiteConfigFn ECR repository (storage/ecr/tenant-site-config) — the repo itself is owned there, not created in this module"
  type        = string
  sensitive   = true
}

variable "tenant_table_name" {
  description = "Name of the tenant DynamoDB table, passed as an environment variable"
  type        = string
  sensitive   = false
}

variable "location_table_name" {
  description = "Name of the location DynamoDB table, passed as an environment variable"
  type        = string
  sensitive   = false
}

variable "turnstile_site_key" {
  description = "Public Cloudflare Turnstile site key the tenant sites render (platform-wide widget)"
  type        = string
  sensitive   = false
}

variable "region" {
  description = "AWS region this Lambda's log group, ECR repository, and image push target live in"
  type        = string
  sensitive   = false
}

variable "location_id_index_name" {
  description = "Name of the location table's locationId GSI - resolves a {locationId} from the URL to its tenant"
  type        = string
  sensitive   = false
}

variable "stripe_publishable_key" {
  description = "Publishable key (pk_...) of the platform Stripe account. Sites initialise Stripe.js with it plus { stripeAccount: <tenant's acct_> } for card-on-file and Payment Element flows on the restaurant's connected account"
  type        = string
  sensitive   = false
}
