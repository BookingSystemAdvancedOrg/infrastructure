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

variable "request_guard_table_name" {
  type = string
}

variable "request_guard_table_arn" {
  type = string
}

variable "alert_topic_arn" {
  type = string
}

variable "enabled" {
  type = bool
}

variable "monthly_answers" {
  type = object({
    per_tenant = number
    total      = number
  })
}

variable "bedrock_client" {
  type = string
}

variable "bedrock_model_id" {
  type = string
}
