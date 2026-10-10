variable "environment" {
  description = "The environment to deploy to (dev or prod)"
  type        = string
  sensitive   = false
}

variable "role_arn" {
  description = "ARN of the ReservationRemindersFn execution role (security/iam/reservation-reminders)"
  type        = string
  sensitive   = true
}

variable "ecr_repository_url" {
  description = "Repository URL of the ReservationRemindersFn ECR repository (storage/ecr/reservation-reminders)"
  type        = string
  sensitive   = true
}

variable "scheduler_invoke_role_arn" {
  description = "ARN of the role EventBridge Scheduler assumes to invoke this function (security/iam/scheduler-invoke-reservation-reminders)"
  type        = string
  sensitive   = true
}

variable "tenant_table_name" {
  description = "Name of the tenant DynamoDB table"
  type        = string
  sensitive   = false
}

variable "location_table_name" {
  description = "Name of the location DynamoDB table"
  type        = string
  sensitive   = false
}

variable "location_id_index_name" {
  description = "Name of the location table's locationId GSI"
  type        = string
  sensitive   = false
}

variable "reservation_table_name" {
  description = "Name of the reservation DynamoDB table"
  type        = string
  sensitive   = false
}
