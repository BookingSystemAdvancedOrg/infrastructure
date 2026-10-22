variable "environment" {
  description = "The environment to deploy to (dev or prod)"
  type        = string
  sensitive   = false
}

variable "role_arn" {
  description = "ARN of the insights-rollup execution role (security/iam/insights-rollup)"
  type        = string
  sensitive   = true
}

variable "ecr_repository_url" {
  description = "Repository URL of the insights-rollup ECR repository (storage/ecr/insights-rollup)"
  type        = string
  sensitive   = true
}

variable "scheduler_invoke_role_arn" {
  description = "ARN of the role EventBridge Scheduler assumes to invoke this function"
  type        = string
  sensitive   = true
}

variable "schedule_expression" {
  description = "When the nightly run happens (rate() or cron(), UTC)"
  type        = string
  sensitive   = false
}

variable "reserved_concurrency" {
  description = "Reserved concurrent executions (1 = one run at a time; -1 = unreserved, for accounts whose concurrency quota is still the 10 default)"
  type        = number
  sensitive   = false
  default     = -1
}

variable "insights_table_name" {
  type = string
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

variable "published_layout_snapshot_table_name" {
  type = string
}

variable "marketing_table_name" {
  type = string
}
