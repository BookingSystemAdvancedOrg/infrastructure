variable "environment" {
  description = "The environment to deploy to (dev or prod)"
  type        = string
}

variable "region" {
  description = "AWS region"
  type        = string
}

variable "ecr_repository_urls" {
  description = "ECR repository URL per function: print-jobs, print-device"
  type        = map(string)
  sensitive   = true
}

variable "tenant_table_name" {
  description = "Tenant table (tenant context)"
  type        = string
}

variable "location_table_name" {
  description = "Location table (tenant context, time zone and name on the ticket)"
  type        = string
}

variable "location_id_index_name" {
  description = "byLocationId index of the location table"
  type        = string
}

variable "user_table_name" {
  description = "User table: staff location check on the admin routes"
  type        = string
}

variable "order_table_name" {
  description = "Order table: tickets are rendered from the order"
  type        = string
}

variable "order_table_arn" {
  description = "Order table ARN"
  type        = string
}

variable "order_stream_arn" {
  description = "Order table stream ARN (paid and cancelled orders)"
  type        = string
}

variable "print_table_name" {
  description = "Print table (storage/dynamodb/print)"
  type        = string
}

variable "print_table_arn" {
  description = "Print table ARN"
  type        = string
}

variable "print_stream_dlq_arn" {
  description = "DLQ for order stream batches print-jobs failed (storage/sqs/dead-letter, drained by dlq-replay)"
  type        = string
}

variable "request_guard_table_name" {
  description = "Request guard table: failed printer logins per IP address"
  type        = string
}

variable "request_guard_table_arn" {
  description = "Request guard table ARN"
  type        = string
}

variable "print_server_url" {
  description = "CloudPRNT server URL without the device id (<api endpoint>/print/cloudprnt), shown in admin when a printer is added"
  type        = string
}

variable "alert_topic_arn" {
  description = "SNS topic for alarms (monitoring/alerts)"
  type        = string
}
