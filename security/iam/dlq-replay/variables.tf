variable "environment" {
  description = "The environment to deploy to (dev or prod)"
  type        = string
  sensitive   = false
}

variable "lifecycle_stream_dlq_arn" {
  description = "ARN of catering-lifecycle-stream-dlq"
  type        = string
  sensitive   = false
}

variable "notification_stream_dlq_arn" {
  description = "ARN of notification-stream-dlq"
  type        = string
  sensitive   = false
}

variable "scheduled_invocation_dlq_arn" {
  description = "ARN of scheduled-invocation-dlq"
  type        = string
  sensitive   = false
}

variable "catering_lifecycle_function_arn" {
  description = "ARN of the catering-lifecycle Lambda - redelivery target"
  type        = string
  sensitive   = false
}

variable "notification_function_arn" {
  description = "ARN of the NotificationFn Lambda - redelivery target"
  type        = string
  sensitive   = false
}

variable "no_show_check_function_arn" {
  description = "ARN of the no-show-check Lambda - redelivery target"
  type        = string
  sensitive   = false
}

variable "reactivate_menu_item_function_arn" {
  description = "ARN of the reactivate-menu-item Lambda - redelivery target"
  type        = string
  sensitive   = false
}

variable "expire_layout_version_function_arn" {
  description = "ARN of the expire-layout-version Lambda - redelivery target"
  type        = string
  sensitive   = false
}

variable "catering_requests_stream_arn" {
  description = "ARN of the catering-requests table's DynamoDB Stream"
  type        = string
  sensitive   = false
}

variable "reservation_stream_arn" {
  description = "ARN of the reservation table's DynamoDB Stream"
  type        = string
  sensitive   = false
}

variable "order_stream_arn" {
  description = "ARN of the order table's DynamoDB Stream"
  type        = string
  sensitive   = false
}

variable "alert_topic_arn" {
  description = "ARN of the alerts SNS topic - escalations are published there"
  type        = string
  sensitive   = false
}

variable "region" {
  description = "AWS region this Lambda's log group lives in"
  type        = string
  sensitive   = false
}
