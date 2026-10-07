variable "environment" {
  description = "The environment to deploy to (dev or prod)"
  type        = string
  sensitive   = false
}

variable "catering_requests_table_arn" {
  description = "ARN of the catering-requests DynamoDB table — item-level read/write (no Scan/DeleteItem) for request and capacity items"
  type        = string
  sensitive   = false
}

variable "catering_request_history_table_arn" {
  description = "ARN of the catering-request-history DynamoDB table — append-only (PutItem), for the first audit entry of every request"
  type        = string
  sensitive   = false
}

variable "turnstile_secret_arn" {
  description = "ARN of the Cloudflare Turnstile secret key secret — verified on every public submit"
  type        = string
  sensitive   = false
}

variable "link_signing_key_secret_arn" {
  description = "ARN of the magic-link HMAC key secret — used to build the customer's order link"
  type        = string
  sensitive   = false
}

variable "location_table_arn" {
  description = "ARN of the location DynamoDB table — read-only access to validate location and fetch catering settings"
  type        = string
  sensitive   = false
}

variable "catering_discount_tiers_table_arn" {
  description = "ARN of the catering-discount-tiers DynamoDB table — read-only access to calculate volume discounts at submission time"
  type        = string
  sensitive   = false
}

variable "menu_table_arn" {
  description = "ARN of the menu DynamoDB table — read-only access to validate line items and capture price snapshots"
  type        = string
  sensitive   = false
}

variable "region" {
  description = "AWS region this Lambda's log group lives in"
  type        = string
  sensitive   = false
}
