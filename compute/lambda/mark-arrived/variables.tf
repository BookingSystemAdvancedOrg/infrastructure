variable "environment" {
  description = "The environment to deploy to (dev or prod)"
  type        = string
  sensitive   = false
}

variable "role_arn" {
  description = "ARN of the MarkArrivedFn execution role (security/iam/mark-arrived)"
  type        = string
  sensitive   = true
}

variable "ecr_repository_url" {
  description = "Repository URL of the MarkArrivedFn ECR repository (storage/ecr/mark-arrived) — the repo itself is owned there, not created in this module"
  type        = string
  sensitive   = true
}

variable "reservation_table_name" {
  description = "Name of the reservation DynamoDB table, passed as an environment variable for the handler's SDK calls"
  type        = string
  sensitive   = false
}

variable "region" {
  description = "AWS region this Lambda's log group, ECR repository, and image push target live in"
  type        = string
  sensitive   = false
}

variable "tenant_table_name" {
  description = "Name of the tenant DynamoDB table - read by the shared tenant-context check (tenant status, plan features, Stripe account, sender)"
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

variable "slot_occupancy_table_name" {
  description = "Name of the slot occupancy DynamoDB table - table holds and locks"
  type        = string
  sensitive   = false
}

variable "published_layout_snapshot_table_name" {
  description = "Name of the published layout snapshot DynamoDB table - bookable tables"
  type        = string
  sensitive   = false
}

variable "user_table_name" {
  description = "Name of the user DynamoDB table - staff users' assigned location"
  type        = string
  sensitive   = false
}

variable "stripe_api_version" {
  description = "Pinned Stripe-Version header for the card-guarantee calls"
  type        = string
  sensitive   = false
}

variable "stripe_secret_arn" {
  description = "ARN of the platform Stripe API key secret"
  type        = string
  sensitive   = false
}
