variable "environment" {
  description = "The environment to deploy to (dev or prod)"
  type        = string
  sensitive   = false
}

variable "region" {
  description = "AWS region of the function and its log group"
  type        = string
  sensitive   = false
}

variable "tenant_table_arn" {
  description = "ARN of the tenant table"
  type        = string
  sensitive   = false
}

variable "data_table_arns" {
  description = "ARNs of the tables whose tenant partitions are deleted: the location-keyed tables, catering history, marketing and location"
  type        = list(string)
  sensitive   = false
}

variable "user_table_arn" {
  description = "ARN of the user table"
  type        = string
  sensitive   = false
}

variable "user_tenant_index_name" {
  description = "Name of the user table's byTenant GSI"
  type        = string
  sensitive   = false
}

variable "tenant_user_pool_arn" {
  description = "ARN of the tenant (restaurant staff) Cognito user pool"
  type        = string
  sensitive   = false
}

variable "menu_image_bucket_arn" {
  description = "ARN of the menu image bucket (menu-images/<tenantId>/...)"
  type        = string
  sensitive   = false
}

variable "alert_topic_arn" {
  description = "ARN of the operator alert topic (summary email per run)"
  type        = string
  sensitive   = false
}

variable "protected_zone_ids" {
  description = "Hosted zone ids this role may never change or delete (the platform's own zones)"
  type        = list(string)
  sensitive   = false
  default     = []
}
