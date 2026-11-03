variable "environment" {
  description = "The environment to deploy to (dev or prod)"
  type        = string
  sensitive   = false
}

variable "region" {
  type = string
}

variable "ecr_repository_urls" {
  description = "ECR repository URL per function: site-builder, site-builder-render"
  type        = map(string)
}

variable "tenant_table_name" {
  type = string
}

variable "tenant_table_arn" {
  type = string
}

variable "location_table_name" {
  type = string
}

variable "location_id_index_name" {
  type = string
}

variable "sites_bucket_name" {
  description = "The restaurant sites bucket (sites/<tenantId>/...)"
  type        = string
}

variable "request_guard_table_name" {
  type = string
}

variable "request_guard_table_arn" {
  type = string
}

variable "site_domain" {
  description = "Restaurant sites' parent domain (<slug>.<domain>) for preview links"
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
