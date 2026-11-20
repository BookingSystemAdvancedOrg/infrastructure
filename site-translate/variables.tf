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

variable "tenant_table_arn" {
  type = string
}

variable "request_guard_table_name" {
  type = string
}

variable "request_guard_table_arn" {
  type = string
}

variable "alert_topic_arn" {
  type = string
}

variable "site_waf_secret" {
  description = "Shared secret the sites' CloudFront sends as x-booqy-waf (root random_password.site_waf_edge)"
  type        = string
  sensitive   = true
}

variable "cloudfront_edge_secret" {
  description = "Shared secret the sites' CloudFront sends with the viewer host and IP (root random_password.cloudfront_edge)"
  type        = string
  sensitive   = true
}

variable "reserved_concurrency" {
  description = "Reserved concurrency of the function: bounds Translate throttling and cost"
  type        = number
  default     = 10
}

variable "ip_requests_per_5min" {
  description = "Translate requests per viewer IP per 5 minutes (429 over it)"
  type        = number
}

variable "ip_chars_per_hour" {
  description = "New (billed) characters per viewer IP per hour; over it, misses stay Swedish"
  type        = number
}

variable "tenant_chars_per_30d" {
  description = "New (billed) characters per restaurant per 30 days; over it, misses stay Swedish"
  type        = number
}

variable "global_chars_per_30d" {
  description = "New (billed) characters for the whole platform per 30 days; over it, misses stay Swedish"
  type        = number
}
