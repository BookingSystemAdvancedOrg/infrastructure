variable "environment" {
  description = "The environment to deploy to (dev or prod)"
  type        = string
  sensitive   = false
}

variable "menu_table_arn" {
  description = "ARN of the menu DynamoDB table — the only resource this role is allowed to access"
  type        = string
  sensitive   = false
}

variable "region" {
  description = "AWS region this Lambda's log group lives in"
  type        = string
  sensitive   = false
}

variable "scheduled_invocation_dlq_arn" {
  description = "ARN of the scheduled-invocation DLQ - this role sends the function's failed asynchronous invocations there"
  type        = string
  sensitive   = false
}
