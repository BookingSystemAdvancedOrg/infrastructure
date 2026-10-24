variable "environment" {
  description = "The environment to deploy to (dev or prod)"
  type        = string
}

variable "region" {
  description = "AWS region"
  type        = string
}

variable "ecr_repository_url" {
  description = "ECR repository URL of the accounting function"
  type        = string
  sensitive   = true
}

variable "tenant_table_name" {
  description = "Tenant table (tenant context; company name and org number)"
  type        = string
}

variable "location_table_name" {
  description = "Location table (tenant context; the accounting mapping)"
  type        = string
}

variable "location_table_arn" {
  description = "Location table ARN (UpdateItem on accounting only)"
  type        = string
}

variable "location_id_index_name" {
  description = "byLocationId index of the location table"
  type        = string
}

variable "user_table_name" {
  description = "User table: tenant context"
  type        = string
}

variable "order_table_name" {
  description = "Order table: orders and card payments"
  type        = string
}

variable "order_table_arn" {
  description = "Order table ARN"
  type        = string
}

variable "reservation_table_name" {
  description = "Reservation table: card guarantee fees"
  type        = string
}

variable "reservation_table_arn" {
  description = "Reservation table ARN"
  type        = string
}

variable "catering_requests_table_name" {
  description = "Catering requests table"
  type        = string
}

variable "catering_requests_table_arn" {
  description = "Catering requests table ARN"
  type        = string
}

variable "catering_history_table_name" {
  description = "Catering request history table: signed offers and audit entries"
  type        = string
}

variable "catering_history_table_arn" {
  description = "Catering request history table ARN"
  type        = string
}

variable "kassa_table_name" {
  description = "Kassa table: the location's registers"
  type        = string
}

variable "kassa_table_arn" {
  description = "Kassa table ARN"
  type        = string
}

variable "kassa_journal_table_name" {
  description = "Kassa journal: receipts and returns per day"
  type        = string
}

variable "kassa_journal_table_arn" {
  description = "Kassa journal table ARN"
  type        = string
}

variable "stripe_secret_arn" {
  description = "Secrets Manager secret with the platform Stripe key"
  type        = string
}

variable "stripe_api_version" {
  description = "Stripe-Version header"
  type        = string
}

variable "alert_topic_arn" {
  description = "SNS topic for alarms (monitoring/alerts)"
  type        = string
}
