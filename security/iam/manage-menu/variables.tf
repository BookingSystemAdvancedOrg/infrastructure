variable "environment" {
  description = "The environment to deploy to (dev or prod)"
  type        = string
  sensitive   = false
}

variable "menu_table_arn" {
  description = "ARN of the menu DynamoDB table - the only resource this role is allowed to access"
  type        = string
  sensitive   = false
}

variable "region" {
  description = "AWS region this Lambda's log group lives in"
  type        = string
  sensitive   = false
}

variable "scheduler_invoke_role_arn" {
  description = "ARN of the role handed to EventBridge Scheduler when creating/updating a reactivate-menu-item schedule - this role is allowed to iam:PassRole it, scoped to PassedToService = scheduler.amazonaws.com"
  type        = string
  sensitive   = false
}
