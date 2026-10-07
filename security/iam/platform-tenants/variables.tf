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

variable "user_table_arn" {
  description = "ARN of the user DynamoDB table"
  type        = string
  sensitive   = false
}

variable "tenant_user_pool_arn" {
  description = "ARN of the tenant Cognito user pool (storage/cognito)"
  type        = string
  sensitive   = false
}

variable "onboarding_state_machine_arn" {
  description = "ARN of the tenant onboarding state machine"
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
  description = "ARN of the platform Stripe API key secret (security/secrets/platform)"
  type        = string
  sensitive   = false
}

variable "region" {
  description = "AWS region this Lambda's log group lives in"
  type        = string
  sensitive   = false
}
