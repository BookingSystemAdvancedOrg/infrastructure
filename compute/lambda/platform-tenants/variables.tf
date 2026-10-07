variable "environment" {
  description = "The environment to deploy to (dev or prod)"
  type        = string
  sensitive   = false
}

variable "role_arn" {
  description = "ARN of the PlatformTenantsFn execution role (security/iam/platform-tenants)"
  type        = string
  sensitive   = true
}

variable "ecr_repository_url" {
  description = "Repository URL of the PlatformTenantsFn ECR repository (storage/ecr/platform-tenants) — the repo itself is owned there, not created in this module"
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

variable "location_id_index_name" {
  description = "Name of the location table's locationId GSI"
  type        = string
  sensitive   = false
}

variable "user_table_name" {
  description = "Name of the user DynamoDB table, passed as an environment variable"
  type        = string
  sensitive   = false
}

variable "user_tenant_index_name" {
  description = "Name of the user table's tenantId GSI"
  type        = string
  sensitive   = false
}

variable "tenant_user_pool_id" {
  description = "ID of the tenant Cognito user pool"
  type        = string
  sensitive   = false
}

variable "owner_group_name" {
  description = "Cognito group of restaurant owners"
  type        = string
  sensitive   = false
}

variable "onboarding_state_machine_arn" {
  description = "ARN of the tenant onboarding state machine, started on tenant creation"
  type        = string
  sensitive   = false
}

variable "domain_attach_state_machine_arn" {
  description = "ARN of the custom-domain attach state machine"
  type        = string
  sensitive   = false
}

variable "domain_detach_state_machine_arn" {
  description = "ARN of the custom-domain detach state machine"
  type        = string
  sensitive   = false
}

variable "offboarding_state_machine_arn" {
  description = "ARN of the tenant offboarding state machine"
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

variable "platform_domain" {
  description = "Domain the platform owns (empty = tenant subdomains/custom domains not available yet)"
  type        = string
  sensitive   = false
}

variable "tenant_domain_cname_target" {
  description = "CNAME target a customer points their domain at (CloudFront connection group routing endpoint) - empty while platform_domain is unset"
  type        = string
  sensitive   = false
}

variable "admin_app_url" {
  description = "URL of the shared restaurant admin app (Stripe onboarding return/refresh URLs)"
  type        = string
  sensitive   = false
}

variable "platform_admin_app_url" {
  description = "URL of the platform admin app (Stripe account-link return/refresh URLs for operators)"
  type        = string
  sensitive   = false
}

variable "region" {
  description = "AWS region this Lambda's log group, ECR repository, and image push target live in"
  type        = string
  sensitive   = false
}

variable "operator_user_pool_id" {
  description = "ID of the operator user pool - the Operators page manages its accounts"
  type        = string
  sensitive   = false
}

variable "operator_group_name" {
  description = "Group every operator is added to (and the only one allowed to use this API)"
  type        = string
  sensitive   = false
}
