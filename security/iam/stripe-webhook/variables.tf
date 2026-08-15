variable "environment" {
  description = "The environment to deploy to (dev or prod)"
  type        = string
  sensitive   = false
}

variable "location_table_arn" {
  description = "ARN of the location DynamoDB table — read-only for this role"
  type        = string
  sensitive   = false
}

variable "reservation_table_arn" {
  description = "ARN of the reservation DynamoDB table — full access for this role"
  type        = string
  sensitive   = false
}

variable "payment_delinquency_table_arn" {
  description = "ARN of the payment delinquency DynamoDB table — full access for this role"
  type        = string
  sensitive   = false
}

variable "scheduler_invoke_role_arn" {
  description = "ARN of the role EventBridge Scheduler assumes to invoke no-show-check — this role must be allowed to pass it to the Scheduler service"
  type        = string
  sensitive   = true
}

variable "region" {
  description = "AWS region this Lambda's log group lives in"
  type        = string
  sensitive   = false
}
