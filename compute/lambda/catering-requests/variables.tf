variable "environment" {
  description = "The environment to deploy to (dev or prod)"
  type        = string
  sensitive   = false
}

variable "role_arn" {
  description = "ARN of the IAM execution role for this Lambda"
  type        = string
  sensitive   = true
}

variable "ecr_repository_url" {
  description = "ECR repository URL for the catering-requests container image"
  type        = string
  sensitive   = true
}

variable "catering_requests_table_name" {
  description = "Name of the catering-requests DynamoDB table"
  type        = string
  sensitive   = false
}

variable "location_table_name" {
  description = "Name of the location DynamoDB table — used to validate location and read catering settings at request time"
  type        = string
  sensitive   = false
}

variable "catering_discount_tiers_table_name" {
  description = "Name of the catering-discount-tiers DynamoDB table — used to calculate volume discounts at submission time"
  type        = string
  sensitive   = false
}

variable "menu_table_name" {
  description = "Name of the menu DynamoDB table — used to validate line items and capture price snapshots"
  type        = string
  sensitive   = false
}

variable "region" {
  description = "AWS region — passed to the function as an environment variable"
  type        = string
  sensitive   = false
}

variable "catering_request_history_table_name" {
  description = "Name of the catering-request-history DynamoDB table, passed as an environment variable for the first audit entry"
  type        = string
  sensitive   = false
}

variable "turnstile_secret_arn" {
  description = "ARN of the Cloudflare Turnstile secret key secret - the handler verifies the submit's Turnstile token with it"
  type        = string
  sensitive   = false
}

variable "link_signing_key_secret_arn" {
  description = "ARN of the magic-link HMAC key secret - the handler builds the customer's order link with it"
  type        = string
  sensitive   = false
}

variable "customer_site_url" {
  description = "Base URL of the customer front-end, e.g. https://<distribution_domain_name> - base of the customer's magic link"
  type        = string
  sensitive   = false
}

variable "tenant_table_name" {
  description = "Name of the tenant DynamoDB table - read by the shared tenant-context check (tenant status, plan features, Stripe account, sender)"
  type        = string
  sensitive   = false
}

variable "location_id_index_name" {
  description = "Name of the location table's locationId GSI - resolves a {locationId} from the URL to its tenant"
  type        = string
  sensitive   = false
}
