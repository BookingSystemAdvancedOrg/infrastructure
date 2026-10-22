variable "environment" {
  description = "The environment to deploy to (dev or prod)"
  type        = string
  sensitive   = false
}

variable "role_arn" {
  description = "ARN of the insights execution role (security/iam/insights)"
  type        = string
  sensitive   = true
}

variable "ecr_repository_url" {
  description = "Repository URL of the insights ECR repository (storage/ecr/insights)"
  type        = string
  sensitive   = true
}

variable "insights_table_name" {
  type = string
}

variable "tenant_table_name" {
  type = string
}

variable "location_table_name" {
  type = string
}

variable "location_id_index_name" {
  type = string
}

variable "user_table_name" {
  description = "User table: a staff caller's assigned location"
  type        = string
}

variable "reservation_table_name" {
  type = string
}

variable "order_table_name" {
  type = string
}

variable "catering_requests_table_name" {
  type = string
}

variable "published_layout_snapshot_table_name" {
  type = string
}

variable "marketing_table_name" {
  type = string
}
