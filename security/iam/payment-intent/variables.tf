variable "environment" {
  description = "The environment to deploy to (dev or prod)"
  type        = string
  sensitive   = false
}

variable "order_table_arn" {
  description = "ARN of the order DynamoDB table - the only resource this role is allowed to access"
  type        = string
  sensitive   = false
}

variable "region" {
  description = "AWS region this Lambda's log group lives in"
  type        = string
  sensitive   = false
}

variable "stripe_secret_arn" {
  description = "ARN of the platform Stripe API key secret (security/secrets/platform)"
  type        = string
  sensitive   = false
}

variable "menu_table_arn" {
  description = "ARN of the menu table (prices are read from it)"
  type        = string
  sensitive   = false
}

variable "turnstile_secret_arn" {
  description = "ARN of the Turnstile secret (bot check on the order form)"
  type        = string
  sensitive   = false
}

variable "request_guard_table_arn" {
  description = "ARN of the attempt-counter table (request_guard)"
  type        = string
  sensitive   = false
}
