variable "environment" {
  description = "The environment to deploy to (dev or prod)"
  type        = string
  sensitive   = false
}

variable "region" {
  type = string
}

variable "finance_table_arn" {
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

variable "log_group_names" {
  description = "Log groups (names) the function may run Logs Insights queries over"
  type        = list(string)
}

variable "alert_topic_arn" {
  type = string
}
