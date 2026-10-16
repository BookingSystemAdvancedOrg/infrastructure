variable "environment" {
  description = "The environment to deploy to (dev or prod)"
  type        = string
  sensitive   = false
}

variable "catering_requests_stream_arn" {
  description = "ARN of the catering-requests table's DynamoDB Stream"
  type        = string
  sensitive   = false
}

variable "lifecycle_stream_dlq_arn" {
  description = "ARN of the SQS DLQ the stream event source mapping sends failed batches to"
  type        = string
  sensitive   = false
}

variable "catering_requests_table_arn" {
  description = "ARN of the catering-requests DynamoDB table"
  type        = string
  sensitive   = false
}

variable "catering_request_history_table_arn" {
  description = "ARN of the catering-request-history DynamoDB table (append-only offer versions and audit log)"
  type        = string
  sensitive   = false
}

variable "location_table_arn" {
  description = "ARN of the location DynamoDB table — read-only, for cateringSettings"
  type        = string
  sensitive   = false
}

variable "stripe_secret_arn" {
  description = "ARN of the platform Stripe API key secret (security/secrets/platform)"
  type        = string
  sensitive   = false
}

variable "schedule_group_name" {
  description = "Name of the EventBridge Scheduler group all catering schedules live in"
  type        = string
  sensitive   = false
}

variable "scheduler_invoke_role_arn" {
  description = "ARN of the role EventBridge Scheduler assumes to invoke catering-lifecycle - the only role this function may pass"
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
