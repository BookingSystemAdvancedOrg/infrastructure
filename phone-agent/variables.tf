variable "environment" {
  description = "The environment to deploy to (dev or prod)"
  type        = string
  sensitive   = false
}

variable "region" {
  type = string
}

variable "ecr_repository_urls" {
  description = "phone-agent, phone-agent-call, phone-agent-jobs => ECR repository URL"
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

variable "user_table_name" {
  type = string
}

variable "user_table_arn" {
  type = string
}

variable "user_tenant_index_name" {
  type = string
}

variable "tool_function_arns" {
  description = "The existing functions the agent's tools invoke, by name => live alias ARN"
  type        = map(string)

  validation {
    condition     = alltrue([for k in ["tenant-site-config", "get-availability", "create-pending-reservation", "get-reservation", "mark-arrived", "get-menu", "list-layout-version"] : contains(keys(var.tool_function_arns), k)])
    error_message = "tool_function_arns must name the seven tool functions."
  }
}

variable "notification_function_arn" {
  type = string
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

variable "voice_client" {
  type = string
}

variable "telephony_client" {
  type = string
}

variable "agent_model_client" {
  type = string
}

variable "phone_agent_model_id" {
  type = string
}

variable "daily_minutes_alarm" {
  description = "Alarm when all tenants together use more minutes than this in a day [NEEDS YOUR OK]"
  type        = number
  default     = 600
}
