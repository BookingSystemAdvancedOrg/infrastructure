variable "environment" {
  description = "The environment to deploy to (dev or prod)"
  type        = string
  sensitive   = false
}

variable "region" {
  type = string
}

variable "insights_table_arn" {
  type = string
}

variable "tenant_table_arn" {
  type = string
}

variable "location_table_arn" {
  type = string
}

variable "reservation_table_arn" {
  type = string
}

variable "order_table_arn" {
  type = string
}

variable "catering_requests_table_arn" {
  type = string
}

variable "published_layout_snapshot_table_arn" {
  type = string
}

variable "marketing_table_arn" {
  type = string
}
