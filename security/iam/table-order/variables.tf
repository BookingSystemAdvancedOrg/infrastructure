variable "environment" {
  description = "The environment to deploy to (dev or prod)"
  type        = string
  sensitive   = false
}

variable "region" {
  description = "AWS region this Lambda's log group lives in"
  type        = string
  sensitive   = false
}

variable "table_order_table_arn" {
  description = "ARN of the table-order DynamoDB table (read/write)"
  type        = string
  sensitive   = false
}

variable "menu_table_arn" {
  description = "ARN of the menu DynamoDB table (read only)"
  type        = string
  sensitive   = false
}

variable "print_table_arn" {
  description = "ARN of the print DynamoDB table (tickets and print jobs, base table only)"
  type        = string
  sensitive   = false
}

variable "published_layout_snapshot_table_arn" {
  description = "ARN of the published layout snapshot DynamoDB table (GetItem only)"
  type        = string
  sensitive   = false
}

variable "reservation_table_arn" {
  description = "ARN of the reservation DynamoDB table (read only, base table)"
  type        = string
  sensitive   = false
}
