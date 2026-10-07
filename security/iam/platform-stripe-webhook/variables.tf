variable "environment" {
  description = "The environment to deploy to (dev or prod)"
  type        = string
  sensitive   = false
}

variable "tenant_table_arn" {
  description = "ARN of the tenant DynamoDB table (storage/dynamodb/tenant)"
  type        = string
  sensitive   = false
}

variable "connect_webhook_secret_arn" {
  description = "ARN of the platform Connect webhook endpoint's signing secret (payments/stripe)"
  type        = string
  sensitive   = false
}

variable "billing_webhook_secret_arn" {
  description = "ARN of the platform billing webhook endpoint's signing secret (payments/stripe)"
  type        = string
  sensitive   = false
}

variable "stripe_secret_arn" {
  description = "ARN of the platform Stripe API key secret (security/secrets/platform)"
  type        = string
  sensitive   = false
}

variable "region" {
  description = "AWS region this Lambda's log group lives in"
  type        = string
  sensitive   = false
}
