variable "environment" {
  description = "The environment to deploy to (dev or prod)"
  type        = string
  sensitive   = false
}

variable "tenant_table_arn" {
  description = "ARN of the tenant DynamoDB table (storage/dynamodb/tenant)"
  type        = string
  sensitive   = false
}

variable "location_table_arn" {
  description = "ARN of the location DynamoDB table"
  type        = string
  sensitive   = false
}

variable "location_id_index_name" {
  description = "Name of the location table's locationId GSI"
  type        = string
  sensitive   = false
}

variable "role_names" {
  description = "Execution roles to attach the policy to, keyed by a stable name (keys must be known at plan time)"
  type        = map(string)
  sensitive   = false
}

variable "user_table_arn" {
  description = "ARN of the user DynamoDB table (storage/dynamodb/user)"
  type        = string
  sensitive   = false
}

variable "staff_check_role_names" {
  description = "Roles of the functions staff_user may call - they may read a user profile by key (GetItem) to check the caller's assigned location and status"
  type        = map(string)
  default     = {}
}
