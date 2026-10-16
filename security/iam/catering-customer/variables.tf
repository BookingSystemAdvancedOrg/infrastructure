variable "environment" {
  description = "The environment to deploy to (dev or prod)"
  type        = string
  sensitive   = false
}

variable "catering_requests_table_arn" {
  description = "ARN of the catering-requests DynamoDB table"
  type        = string
  sensitive   = false
}

variable "catering_request_history_table_arn" {
  description = "ARN of the catering-request-history DynamoDB table (append-only offer versions and audit log)"
  type        = string
  sensitive   = false
}

variable "location_table_arn" {
  description = "ARN of the location DynamoDB table — read-only, for cateringSettings"
  type        = string
  sensitive   = false
}

variable "catering_documents_bucket_arn" {
  description = "ARN of the catering-documents archive bucket"
  type        = string
  sensitive   = false
}

variable "link_signing_key_secret_arn" {
  description = "ARN of the magic-link HMAC key secret (security/secrets/catering)"
  type        = string
  sensitive   = false
}

variable "signing_provider_secret_arn" {
  description = "ARN of the BankID signing provider credentials secret (security/secrets/catering)"
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
