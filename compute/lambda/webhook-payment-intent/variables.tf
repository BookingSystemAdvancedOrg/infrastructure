variable "environment" {
  description = "The environment to deploy to (dev or prod)"
  type        = string
  sensitive   = false
}

variable "role_arn" {
  description = "ARN of the WebhookPaymentIntentFn execution role (security/iam/webhook-payment-intent)"
  type        = string
  sensitive   = true
}

variable "ecr_repository_url" {
  description = "Repository URL of the WebhookPaymentIntentFn ECR repository (storage/ecr/webhook-payment-intent) — the repo itself is owned there, not created in this module"
  type        = string
  sensitive   = true
}

variable "order_table_name" {
  description = "Name of the order DynamoDB table, passed as an environment variable for the handler's SDK calls"
  type        = string
  sensitive   = false
}

variable "order_stripe_webhook_secret" {
  description = "Signing secret (whsec_...) for this endpoint - the handler verifies the Stripe-Signature header against this value, which is what actually authenticates incoming requests since authorization_type is NONE"
  type        = string
  sensitive   = true
}

variable "region" {
  description = "AWS region this Lambda's log group, ECR repository, and image push target live in"
  type        = string
  sensitive   = false
}
