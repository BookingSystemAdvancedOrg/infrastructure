variable "environment" {
  description = "The environment to deploy to (dev or prod)"
  type        = string
  sensitive   = false
}

variable "location_table_arn" {
  description = "ARN of the location DynamoDB table - read-only for this role"
  type        = string
  sensitive   = false
}

variable "reservation_table_arn" {
  description = "ARN of the reservation DynamoDB table - full access for this role"
  type        = string
  sensitive   = false
}

variable "payment_delinquency_table_arn" {
  description = "ARN of the payment delinquency DynamoDB table - full access for this role"
  type        = string
  sensitive   = false
}

variable "region" {
  description = "AWS region this Lambda's log group lives in"
  type        = string
  sensitive   = false
}

variable "webhook_secret_arn" {
  description = "ARN of the Secrets Manager secret holding this function's Stripe webhook signing secret"
  type        = string
  sensitive   = false
}

variable "stripe_secret_arn" {
  description = "ARN of the platform Stripe API key secret - GetSecretValue on this one secret only"
  type        = string
  sensitive   = false
}
