variable "environment" {
  description = "The environment to deploy to (dev or prod)"
  type        = string
  sensitive   = false
}

variable "region" {
  description = "AWS region of the feature Lambdas"
  type        = string
  sensitive   = false
}

variable "account_id" {
  description = "AWS account id of the feature Lambdas"
  type        = string
  sensitive   = false
}

variable "role_names" {
  description = "Existing caller execution roles by key: guest_privacy, tenant_purge, stripe_webhook, payment_intent, webhook_payment_intent, kassa, accounting, insights, marketing, marketing_send, platform_tenants"
  type        = map(string)
  sensitive   = false

  validation {
    condition = length(setsubtract([
      "guest_privacy", "tenant_purge", "stripe_webhook", "payment_intent", "webhook_payment_intent",
      "kassa", "accounting", "insights", "marketing", "marketing_send", "platform_tenants",
    ], keys(var.role_names))) == 0
    error_message = "role_names must name every hook caller role."
  }
}
