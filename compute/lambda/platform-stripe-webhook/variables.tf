variable "environment" {
  description = "The environment to deploy to (dev or prod)"
  type        = string
  sensitive   = false
}

variable "role_arn" {
  description = "ARN of the PlatformStripeWebhookFn execution role (security/iam/platform-stripe-webhook)"
  type        = string
  sensitive   = true
}

variable "ecr_repository_url" {
  description = "Repository URL of the PlatformStripeWebhookFn ECR repository (storage/ecr/platform-stripe-webhook) — the repo itself is owned there, not created in this module"
  type        = string
  sensitive   = true
}

variable "tenant_table_name" {
  description = "Name of the tenant DynamoDB table, passed as an environment variable"
  type        = string
  sensitive   = false
}

variable "connect_webhook_secret_arn" {
  description = "ARN of the Connect endpoint signing secret"
  type        = string
  sensitive   = false
}

variable "billing_webhook_secret_arn" {
  description = "ARN of the billing endpoint signing secret"
  type        = string
  sensitive   = false
}

variable "stripe_secret_arn" {
  description = "ARN of the platform Stripe API key secret - the handler reads the key at cold start"
  type        = string
  sensitive   = false
}

variable "stripe_api_version" {
  description = "Pinned Stripe API version the handler is coded against"
  type        = string
  sensitive   = false
}

variable "region" {
  description = "AWS region this Lambda's log group, ECR repository, and image push target live in"
  type        = string
  sensitive   = false
}
