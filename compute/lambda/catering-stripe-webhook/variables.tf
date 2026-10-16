variable "environment" {
  description = "The environment to deploy to (dev or prod)"
  type        = string
  sensitive   = false
}

variable "role_arn" {
  description = "ARN of the CateringStripeWebhookFn execution role (security/iam/catering-stripe-webhook)"
  type        = string
  sensitive   = true
}

variable "ecr_repository_url" {
  description = "Repository URL of the CateringStripeWebhookFn ECR repository (storage/ecr/catering-stripe-webhook) — the repo itself is owned there, not created in this module"
  type        = string
  sensitive   = true
}

variable "catering_requests_table_name" {
  description = "Name of the catering-requests DynamoDB table, passed as an environment variable for the handler's SDK calls"
  type        = string
  sensitive   = false
}

variable "catering_request_history_table_name" {
  description = "Name of the catering-request-history DynamoDB table, passed as an environment variable"
  type        = string
  sensitive   = false
}

variable "catering_documents_bucket_name" {
  description = "Name of the catering-documents archive bucket, passed as an environment variable"
  type        = string
  sensitive   = false
}

variable "catering_stripe_webhook_secret_arn" {
  description = "ARN of the Secrets Manager secret holding this endpoint's Stripe signing secret (whsec_...) - created and filled by payments/stripe; the handler verifies the Stripe-Signature header against it"
  type        = string
  sensitive   = false
}

variable "stripe_secret_arn" {
  description = "ARN of the platform Stripe API key secret (security/secrets/platform) - the handler reads the key at cold start and calls Stripe on the tenant's connected account"
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

variable "tenant_table_name" {
  description = "Name of the tenant DynamoDB table - read by the shared tenant-context check (tenant status, plan features, Stripe account, sender)"
  type        = string
  sensitive   = false
}

variable "location_table_name" {
  description = "Name of the location DynamoDB table, passed as an environment variable"
  type        = string
  sensitive   = false
}

variable "location_id_index_name" {
  description = "Name of the location table's locationId GSI - resolves a {locationId} from the URL to its tenant"
  type        = string
  sensitive   = false
}
