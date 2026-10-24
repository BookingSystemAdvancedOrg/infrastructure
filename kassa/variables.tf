variable "environment" {
  description = "The environment to deploy to (dev or prod)"
  type        = string
}

variable "region" {
  description = "AWS region"
  type        = string
}

variable "ecr_repository_url" {
  description = "ECR repository URL of the kassa function"
  type        = string
  sensitive   = true
}

variable "tenant_table_name" {
  description = "Tenant table (tenant context)"
  type        = string
}

variable "location_table_name" {
  description = "Location table (tenant context; address, terminal)"
  type        = string
}

variable "location_id_index_name" {
  description = "byLocationId index of the location table"
  type        = string
}

variable "user_table_name" {
  description = "User table: staff location check"
  type        = string
}

variable "menu_table_name" {
  description = "Menu table: prices when a line is added"
  type        = string
}

variable "menu_table_arn" {
  description = "Menu table ARN"
  type        = string
}

variable "order_table_name" {
  description = "Order table: card payment records and receipt e-mail notices"
  type        = string
}

variable "order_table_arn" {
  description = "Order table ARN"
  type        = string
}

variable "print_table_name" {
  description = "Print table: printer settings and Kassa print jobs"
  type        = string
}

variable "print_table_arn" {
  description = "Print table ARN"
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

variable "certified" {
  description = "Kassa may present receipts as a certified cash register's (needs a real control system; the simulator ignores it)"
  type        = bool
  default     = false
}
