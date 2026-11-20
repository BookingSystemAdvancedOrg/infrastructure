variable "environment" {
  description = "The environment to deploy to (dev or prod)"
  type        = string
  sensitive   = false
}

variable "role_arn" {
  description = "ARN of the TableOrderFn execution role (security/iam/table-order)"
  type        = string
  sensitive   = true
}

variable "ecr_repository_url" {
  description = "Repository URL of the TableOrderFn ECR repository (storage/ecr/table-order) - the repo itself is owned there, not created in this module"
  type        = string
  sensitive   = true
}

variable "table_order_table_name" {
  description = "Name of the table-order DynamoDB table (tabs, locks, idempotency, state version)"
  type        = string
  sensitive   = false
}

variable "menu_table_name" {
  description = "Name of the menu DynamoDB table (dishes and categories, read only)"
  type        = string
  sensitive   = false
}

variable "print_table_name" {
  description = "Name of the print DynamoDB table (stations, printers, tickets and print jobs)"
  type        = string
  sensitive   = false
}

variable "published_layout_snapshot_table_name" {
  description = "Name of the published layout snapshot DynamoDB table (the active floor plan's tables, read only)"
  type        = string
  sensitive   = false
}

variable "reservation_table_name" {
  description = "Name of the reservation DynamoDB table (today's bookings, to link a guest to a table, read only)"
  type        = string
  sensitive   = false
}

variable "tenant_table_name" {
  description = "Name of the tenant DynamoDB table - read by the shared tenant-context check (tenant status, plan features)"
  type        = string
  sensitive   = false
}

variable "location_table_name" {
  description = "Name of the location DynamoDB table, passed as an environment variable"
  type        = string
  sensitive   = false
}

variable "location_id_index_name" {
  description = "Name of the location table's locationId GSI - resolves a {locationId} from the URL to its tenant"
  type        = string
  sensitive   = false
}

variable "user_table_name" {
  description = "Name of the user table (staff are kept to their own location)"
  type        = string
  sensitive   = false
}
