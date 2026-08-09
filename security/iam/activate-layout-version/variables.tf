variable "environment" {
  description = "The environment to deploy to (dev or prod)"
  type        = string
  sensitive   = false
}

variable "published_layout_snapshot_table_arn" {
  description = "ARN of the published layout snapshot DynamoDB table — the only resource this role is allowed to access"
  type        = string
  sensitive   = false
}

variable "scheduler_invoke_role_arn" {
  description = "ARN of the role EventBridge Scheduler assumes to invoke expire-layout-version — this role must be allowed to pass it to the Scheduler service"
  type        = string
  sensitive   = true
}

variable "region" {
  description = "AWS region this Lambda's log group lives in"
  type        = string
  sensitive   = false
}
