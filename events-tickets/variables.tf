variable "environment" {
  description = "The environment to deploy to (dev or prod)"
  type        = string
  sensitive   = false
}

variable "region" {
  type = string
}

variable "ecr_repository_url" {
  type = string
}

variable "tenant_table_name" {
  type = string
}

variable "location_table_name" {
  type = string
}

variable "location_id_index_name" {
  type = string
}

variable "user_table_name" {
  type = string
}

variable "stripe_secret_arn" {
  description = "Platform Stripe key (PaymentIntents and refunds on the connected account)"
  type        = string
}

variable "stripe_api_version" {
  type = string
}

variable "turnstile_required" {
  type = bool
}

variable "turnstile_secret_arn" {
  type = string
}

variable "request_guard_table_name" {
  type = string
}

variable "request_guard_table_arn" {
  type = string
}

variable "notification_function_arn" {
  description = "notification live alias ARN (ticket, transfer, refund and cancel emails, CONTRACTS.md 9.4)"
  type        = string
}

variable "event_bus_name" {
  type = string
}

variable "event_bus_arn" {
  type = string
}

variable "alert_topic_arn" {
  type = string
}

variable "cloudfront_edge_secret" {
  description = "Admin CloudFront shared secret (trusted viewer IP for the request guard)"
  type        = string
  sensitive   = true
}

variable "site_domain" {
  description = "Restaurant sites' slug zone (ticket and transfer links in the emails)"
  type        = string
}

variable "customer_site_url" {
  description = "Dev shared site URL (?restaurang=<slug>), \"\" in prod"
  type        = string
}
