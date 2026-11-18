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

variable "location_table_name" {
  type = string
}

variable "location_table_arn" {
  type = string
}

variable "location_id_index_name" {
  type = string
}

variable "user_table_name" {
  type = string
}

variable "user_table_arn" {
  type = string
}

variable "user_tenant_index_name" {
  type = string
}

variable "menu_table_name" {
  type = string
}

variable "menu_table_arn" {
  type = string
}

variable "print_table_name" {
  type = string
}

variable "print_table_arn" {
  type = string
}

variable "published_layout_snapshot_table_name" {
  type = string
}

variable "published_layout_snapshot_table_arn" {
  type = string
}

variable "google_business_table_name" {
  description = "google-business table (read: CONNECTION, LINK, SKIP rows)"
  type        = string
}

variable "phone_agent_table_name" {
  description = "phone-agent table (read: CONFIG and LOC#<l>#CONFIG rows)"
  type        = string
}

variable "event_bus_name" {
  type = string
}

variable "event_bus_arn" {
  type = string
}

variable "alert_topic_arn" {
  description = "Platform alerts topic: the operators' email when a restaurant finishes Kom igång, and the errors alarm"
  type        = string
}

variable "console_app_url" {
  description = "Booqy Console base URL, for the link in the email"
  type        = string
}
