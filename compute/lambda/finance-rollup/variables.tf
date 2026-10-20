variable "environment" {
  description = "The environment to deploy to (dev or prod)"
  type        = string
  sensitive   = false
}

variable "role_arn" {
  description = "ARN of the finance-rollup execution role (security/iam/finance-rollup)"
  type        = string
  sensitive   = true
}

variable "ecr_repository_url" {
  description = "Repository URL of the finance-rollup ECR repository (storage/ecr/finance-rollup)"
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

variable "finance_table_name" {
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

variable "log_group_names" {
  description = "Log groups of the tenant-aware Lambdas whose request lines are counted per customer (CloudWatch Logs Insights)"
  type        = list(string)
}

variable "usd_to_sek" {
  description = "Exchange rate for showing AWS cost in SEK (root var.aws_usd_to_sek)"
  type        = number
}

variable "cost_allocation" {
  description = "Service lists per allocation bucket (root var.cost_allocation)"
  type = object({
    baseline = list(string)
    email    = list(string)
    sms      = list(string)
  })
}

variable "alert_topic_arn" {
  type = string
}
