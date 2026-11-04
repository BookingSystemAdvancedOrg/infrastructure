variable "environment" {
  description = "The environment to deploy to (dev or prod)"
  type        = string
  sensitive   = false
}

variable "region" {
  description = "AWS region (logs ARNs)"
  type        = string
}

variable "ecr_repository_urls" {
  description = "ECR repository URL per function: guest-crm, guest-crm-sync"
  type        = map(string)
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
  description = "User table (staff location check, via the shared staff-check policy)"
  type        = string
}

variable "consent_table_name" {
  type = string
}

variable "consent_table_arn" {
  type = string
}

variable "marketing_table_name" {
  type = string
}

variable "marketing_table_arn" {
  type = string
}

variable "source_tables" {
  description = "reservation, order and catering (catering-requests) tables: name, arn and stream_arn each"
  type        = map(object({ name = string, arn = string, stream_arn = string }))
}

variable "event_bus_name" {
  type = string
}

variable "event_bus_arn" {
  type = string
}

variable "alert_topic_arn" {
  description = "Ops alert SNS topic for the Errors and DLQ alarms"
  type        = string
}
