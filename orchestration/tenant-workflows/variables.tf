variable "environment" {
  description = "The environment to deploy to (dev or prod)"
  type        = string
  sensitive   = false
}

variable "region" {
  description = "AWS region the state machines run in"
  type        = string
  sensitive   = false
}

variable "tenant_table_name" {
  description = "Name of the tenant DynamoDB table"
  type        = string
  sensitive   = false
}

variable "tenant_table_arn" {
  description = "ARN of the tenant DynamoDB table"
  type        = string
  sensitive   = false
}

variable "user_table_name" {
  description = "Name of the user DynamoDB table (owner profile written at onboarding)"
  type        = string
  sensitive   = false
}

variable "user_table_arn" {
  description = "ARN of the user DynamoDB table"
  type        = string
  sensitive   = false
}

variable "user_tenant_index_name" {
  description = "Name of the user table's tenantId GSI (offboarding lists a tenant's users)"
  type        = string
  sensitive   = false
}

variable "tenant_user_pool_id" {
  description = "ID of the tenant Cognito user pool"
  type        = string
  sensitive   = false
}

variable "tenant_user_pool_arn" {
  description = "ARN of the tenant Cognito user pool"
  type        = string
  sensitive   = false
}

variable "owner_group_name" {
  description = "Cognito group the first owner is added to"
  type        = string
  sensitive   = false
}

variable "stripe_secret_key" {
  description = "Platform Stripe API key for the EventBridge connection the onboarding HTTP tasks authenticate with"
  type        = string
  sensitive   = true
}

variable "stripe_api_version" {
  description = "Stripe-Version header the HTTP tasks pin"
  type        = string
  sensitive   = false
}

variable "default_tax_rates" {
  description = "VAT rates created on every new connected account (see root var.default_tax_rates)"
  type = map(object({
    display_name = string
    percentage   = number
    inclusive    = bool
  }))
  sensitive = false
}

variable "alert_topic_arn" {
  description = "SNS topic (monitoring/alerts) workflow failures are reported to"
  type        = string
  sensitive   = false
}

variable "platform_domain_enabled" {
  description = "Whether the multi-tenant CloudFront distribution exists (root var.platform_domain set)"
  type        = bool
  sensitive   = false
}

variable "platform_domain" {
  description = "Platform domain; tenant subdomains are <slug>.<platform_domain>. Empty when disabled."
  type        = string
  sensitive   = false
}

variable "multitenant_distribution_id" {
  description = "ID of the multi-tenant CloudFront distribution - empty when disabled"
  type        = string
  sensitive   = false
}

variable "multitenant_distribution_arn" {
  description = "ARN of the multi-tenant CloudFront distribution - empty when disabled"
  type        = string
  sensitive   = false
}

variable "connection_group_id" {
  description = "ID of the CloudFront connection group distribution tenants are attached to - empty when disabled"
  type        = string
  sensitive   = false
}

variable "connection_group_arn" {
  description = "ARN of the CloudFront connection group - empty when disabled"
  type        = string
  sensitive   = false
}

variable "cname_target" {
  description = "Routing endpoint customers point their CNAME at - empty when disabled"
  type        = string
  sensitive   = false
}

variable "sites_bucket_name" {
  description = "Name of the tenant-sites bucket - empty when disabled"
  type        = string
  sensitive   = false
}

variable "sites_bucket_arn" {
  description = "ARN of the tenant-sites bucket - empty when disabled"
  type        = string
  sensitive   = false
}

variable "site_placeholder_key" {
  description = "Key of the 'coming soon' page in the tenant-sites bucket that onboarding copies to <tenantId>/index.html"
  type        = string
  sensitive   = false
  default     = "_placeholder/index.html"
}

variable "certificate_check_interval_seconds" {
  description = "How often domain-attach checks whether the customer's certificate has been issued"
  type        = number
  sensitive   = false
  default     = 300
}

variable "max_certificate_checks" {
  description = "Checks before domain-attach gives up waiting for the customer's DNS (default 864 x 5 min = 72 h, ACM's own HTTP-validation window)"
  type        = number
  sensitive   = false
  default     = 864
}
