variable "environment" {
  description = "The environment to deploy to (dev or prod)"
  type        = string
  sensitive   = false
}

variable "role_arn" {
  description = "ARN of the data-retention execution role (security/iam/data-retention)"
  type        = string
  sensitive   = true
}

variable "ecr_repository_url" {
  description = "Repository URL of the data-retention ECR repository (storage/ecr/data-retention)"
  type        = string
  sensitive   = true
}

variable "scheduler_invoke_role_arn" {
  description = "ARN of the role EventBridge Scheduler assumes to invoke this function"
  type        = string
  sensitive   = true
}

variable "schedule_expression" {
  description = "When the sweep runs (rate() or cron(), UTC)"
  type        = string
  sensitive   = false
}

variable "dry_run" {
  description = "true = only log counts, write and delete nothing"
  type        = bool
  sensitive   = false
}

variable "retention_env" {
  description = "RETENTION_* environment variables (the periods, shared/retention.py)"
  type        = map(string)
  sensitive   = false
}

variable "tenant_table_name" {
  type = string
}

variable "location_table_name" {
  type = string
}

variable "reservation_table_name" {
  type = string
}

variable "order_table_name" {
  type = string
}

variable "catering_requests_table_name" {
  type = string
}

variable "catering_request_history_table_name" {
  type = string
}

variable "consent_table_name" {
  type = string
}

variable "consent_tenant_index_name" {
  type = string
}

variable "marketing_table_name" {
  type = string
}

variable "alert_topic_arn" {
  description = "SNS topic for the failure email"
  type        = string
}
