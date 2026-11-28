variable "environment" {
  description = "The environment to deploy to (dev or prod)"
  type        = string
  sensitive   = false
}

variable "reservation_table_arn" {
  description = "ARN of the reservation DynamoDB table - the only resource this role is allowed to access"
  type        = string
  sensitive   = false
}

variable "region" {
  description = "AWS region this Lambda's log group lives in"
  type        = string
  sensitive   = false
}

variable "slot_occupancy_table_arn" {
  description = "ARN of the slot occupancy DynamoDB table (table holds and locks)"
  type        = string
  sensitive   = false
}

variable "published_layout_snapshot_table_arn" {
  description = "ARN of the published layout snapshot DynamoDB table (bookable tables, for moves)"
  type        = string
  sensitive   = false
}

variable "stripe_secret_arn" {
  description = "ARN of the platform Stripe API key secret (security/secrets/platform)"
  type        = string
  sensitive   = false
}

variable "notification_function_arn" {
  description = "Alias ARN of notification:live - the only function this role may invoke (the card link SMS)"
  type        = string
  sensitive   = false
}
