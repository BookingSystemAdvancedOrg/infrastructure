variable "environment" {
  description = "The environment to deploy to (dev or prod)"
  type        = string
}

variable "region" {
  description = "AWS region"
  type        = string
}

variable "ecr_repository_urls" {
  description = "ECR repository URL per function: marketing, marketing-public, marketing-send, marketing-sync"
  type        = map(string)
  sensitive   = true
}

variable "tenant_table_name" {
  description = "Tenant table (tenant context)"
  type        = string
}

variable "location_table_name" {
  description = "Location table (tenant context)"
  type        = string
}

variable "location_id_index_name" {
  description = "byLocationId index of the location table"
  type        = string
}

variable "user_table_name" {
  description = "User table: the owner's own profile for test emails"
  type        = string
}

variable "user_table_arn" {
  description = "User table ARN"
  type        = string
}

variable "menu_table_name" {
  description = "Menu table: dish blocks in email templates"
  type        = string
}

variable "menu_table_arn" {
  description = "Menu table ARN"
  type        = string
}

variable "menu_image_base_url" {
  description = "https base URL menu images are served from (imageKey is appended)"
  type        = string
}

variable "customer_site_url" {
  description = "Shared customer site URL used in dev when a tenant has no domain (?restaurang=<slug>)"
  type        = string
}

variable "admin_app_url" {
  description = "Admin app URL; email links go through its /api (https://restaurant.<domain>/api/m/...)"
  type        = string
}

variable "reservation_table_name" {
  description = "Reservation table name (routes stream records)"
  type        = string
}

variable "reservation_stream_arn" {
  description = "Reservation table stream"
  type        = string
}

variable "order_table_name" {
  description = "Order table name (routes stream records)"
  type        = string
}

variable "order_stream_arn" {
  description = "Order table stream"
  type        = string
}

variable "ses_identity_arn" {
  description = "SES identity the no-reply address belongs to"
  type        = string
}

variable "from_address" {
  description = "No-reply sender address"
  type        = string
}

variable "mail_outbox_bucket_name" {
  description = "Dev mail outbox bucket (empty = send through SES)"
  type        = string
  default     = ""
}

variable "mail_outbox_bucket_arn" {
  description = "Dev mail outbox bucket ARN (empty = none)"
  type        = string
  default     = ""
}

variable "monthly_email_limit" {
  description = "Marketing emails per restaurant per calendar month"
  type        = number
  default     = 5000
}

variable "send_rate" {
  description = "Marketing emails per second (stay well under the account's SES send rate)"
  type        = number
  default     = 10
}
