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

variable "slot_occupancy_table_arn" {
  description = "ARN of the slot occupancy DynamoDB table — read-only for this role"
  type        = string
  sensitive   = false
}

variable "published_layout_snapshot_table_arn" {
  description = "ARN of the published layout snapshot DynamoDB table — read-only for this role"
  type        = string
  sensitive   = false
}

variable "region" {
  description = "AWS region this Lambda's log group lives in"
  type        = string
  sensitive   = false
}
