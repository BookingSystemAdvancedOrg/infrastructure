variable "environment" {
  description = "The environment to deploy to (dev or prod)"
  type        = string
  sensitive   = false
}

variable "role_arn" {
  description = "ARN of the StripeWebhookFn execution role (security/iam/stripe-webhook)"
  type        = string
  sensitive   = true
}

variable "ecr_repository_url" {
  description = "Repository URL of the StripeWebhookFn ECR repository (storage/ecr/stripe-webhook) — the repo itself is owned there, not created in this module"
  type        = string
  sensitive   = true
}

variable "location_table_name" {
  description = "Name of the location DynamoDB table, passed as an environment variable for the handler's SDK calls"
  type        = string
  sensitive   = false
}

variable "reservation_table_name" {
  description = "Name of the reservation DynamoDB table, passed as an environment variable for the handler's SDK calls"
  type        = string
  sensitive   = false
}

variable "payment_delinquency_table_name" {
  description = "Name of the payment delinquency DynamoDB table, passed as an environment variable for the handler's SDK calls"
  type        = string
  sensitive   = false
}

variable "scheduler_invoke_role_arn" {
  description = "ARN of the IAM role handed to EventBridge Scheduler when creating a no-show-check schedule, passed as an environment variable for the handler's SDK calls"
  type        = string
  sensitive   = true
}

variable "no_show_check_function_arn" {
  description = "ARN of the NoShowCheckFn Lambda — the Scheduler target for the no-show-check schedule, passed as an environment variable for the handler's SDK calls"
  type        = string
  sensitive   = false
}

variable "region" {
  description = "AWS region this Lambda's log group, ECR repository, and image push target live in"
  type        = string
  sensitive   = false
}
