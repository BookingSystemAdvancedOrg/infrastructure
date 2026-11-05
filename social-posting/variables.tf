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

variable "menu_table_name" {
  type = string
}

variable "menu_table_arn" {
  type = string
}

variable "menu_image_bucket_name" {
  type = string
}

variable "menu_image_bucket_arn" {
  type = string
}

variable "meta_ads_table_name" {
  description = "Feature A's table (CONNECTION rows, read only)"
  type        = string
}

variable "meta_ads_table_arn" {
  type = string
}

variable "meta_ads_tenant_secret_prefix" {
  description = "Feature A's per-tenant token secrets: <prefix><tenantId> (read only)"
  type        = string
}

variable "meta_client" {
  description = "META_CLIENT: simulator or real (root var.meta_client, A's validated variable)"
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
