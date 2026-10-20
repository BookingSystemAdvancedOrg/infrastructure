variable "environment" {
  description = "The environment to deploy to (dev or prod)"
  type        = string
  sensitive   = false
}

variable "role_arn" {
  description = "ARN of the tenant-purge execution role (security/iam/tenant-purge)"
  type        = string
  sensitive   = true
}

variable "ecr_repository_url" {
  description = "Repository URL of the tenant-purge ECR repository (storage/ecr/tenant-purge)"
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

variable "retention_days" {
  description = "Days an offboarded restaurant's data is kept; used for restaurants offboarded before purgeAt existed"
  type        = number
  sensitive   = false
}

variable "reserved_concurrency" {
  description = "Reserved concurrent executions (1 = one run at a time; -1 = unreserved, for accounts whose concurrency quota is still the 10 default)"
  type        = number
  sensitive   = false
  default     = -1
}

variable "tenant_table_name" {
  type = string
}

variable "location_table_name" {
  type = string
}

variable "user_table_name" {
  type = string
}

variable "user_tenant_index_name" {
  type = string
}

variable "tenant_user_pool_id" {
  type = string
}

variable "location_table_names" {
  description = "Tables partitioned by LOCATION#<locationId> whose partitions are deleted per location"
  type        = list(string)
}

variable "catering_requests_table_name" {
  type = string
}

variable "catering_request_history_table_name" {
  type = string
}

variable "marketing_table_name" {
  type = string
}

variable "menu_image_bucket_name" {
  type = string
}

variable "alert_topic_arn" {
  type = string
}

variable "protected_zone_ids" {
  description = "Hosted zone ids the function must never delete (the platform's own zones)"
  type        = list(string)
  default     = []
}
