variable "environment" {
  description = "The environment to deploy to (dev or prod)"
  type        = string
  sensitive   = false
}

variable "role_arn" {
  description = "ARN of the TenantAccountFn execution role (security/iam/tenant-account)"
  type        = string
  sensitive   = true
}

variable "ecr_repository_url" {
  description = "Repository URL of the TenantAccountFn ECR repository (storage/ecr/tenant-account) — the repo itself is owned there, not created in this module"
  type        = string
  sensitive   = true
}

variable "tenant_table_name" {
  description = "Name of the tenant DynamoDB table, passed as an environment variable"
  type        = string
  sensitive   = false
}

variable "location_table_name" {
  description = "Name of the location DynamoDB table, passed as an environment variable"
  type        = string
  sensitive   = false
}

variable "user_table_name" {
  description = "Name of the user DynamoDB table - staff users' assigned location"
  type        = string
  sensitive   = false
}

variable "stripe_secret_arn" {
  description = "ARN of the platform Stripe API key secret - the handler reads the key at cold start"
  type        = string
  sensitive   = false
}

variable "stripe_api_version" {
  description = "Pinned Stripe API version the handler is coded against"
  type        = string
  sensitive   = false
}

variable "admin_app_url" {
  description = "URL of the shared restaurant admin app (Stripe onboarding return/refresh URLs)"
  type        = string
  sensitive   = false
}

variable "region" {
  description = "AWS region this Lambda's log group, ECR repository, and image push target live in"
  type        = string
  sensitive   = false
}

variable "location_id_index_name" {
  description = "Name of the location table's locationId GSI - resolves a {locationId} from the URL to its tenant"
  type        = string
  sensitive   = false
}
