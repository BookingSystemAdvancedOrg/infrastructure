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

variable "table_name" {
  description = "The support-reports table (storage/dynamodb/support-reports)"
  type        = string
}

variable "table_arn" {
  type = string
}

variable "request_guard_table_name" {
  type = string
}

variable "request_guard_table_arn" {
  type = string
}

variable "alert_topic_arn" {
  description = "Platform alerts topic: errors alarm and one message per new report"
  type        = string
}

variable "console_app_url" {
  description = "Booqy Console base URL, for the Reports link in the notification"
  type        = string
}
