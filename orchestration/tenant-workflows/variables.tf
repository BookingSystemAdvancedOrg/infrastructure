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

variable "tenant_subdomains_enabled" {
  description = "Give each tenant <slug>.<platform_domain> at onboarding (and fall back to it when a primary custom domain is detached). Off = own domains only"
  type        = bool
  sensitive   = false
  default     = false
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

variable "platform_tenants_function_arn" {
  description = "Qualified ARN (live alias) of the platform-tenants Lambda - runs domain-provision's waiting and DNS tasks. Built from the function name in the root module, not taken from the function resource (whose environment holds this module's state machine ARNs)"
  type        = string
  sensitive   = false
}

variable "registration_check_interval_seconds" {
  description = "How often domain-provision checks a domain registration (Route 53 Domains operation)"
  type        = number
  sensitive   = false
  default     = 3600
}

variable "max_registration_checks" {
  description = "Checks before domain-provision gives up on a registration (default 720 x 1 h = 30 days - the .se identity check goes through an AWS Support case)"
  type        = number
  sensitive   = false
  default     = 720
}

variable "nameserver_check_interval_seconds" {
  description = "How often domain-provision checks whether a connected domain's name servers have been switched"
  type        = number
  sensitive   = false
  default     = 600
}

variable "max_nameserver_checks" {
  description = "Checks before domain-provision gives up waiting for the name server switch (default 432 x 10 min = 72 h)"
  type        = number
  sensitive   = false
  default     = 432
}

variable "tenant_data_retention_days" {
  description = "Days an offboarded tenant's data is kept before the tenant-purge Lambda deletes it. Offboarding writes purgeAt = offboarded + this."
  type        = number
}
