variable "environment" {
  description = "The environment to deploy to (dev or prod)"
  type        = string
  sensitive   = false
}

variable "location_table_arn" {
  description = "ARN of the location DynamoDB table — the only resource this role is allowed to access"
  type        = string
  sensitive   = false
}

variable "region" {
  description = "AWS region this Lambda's log group lives in"
  type        = string
  sensitive   = false
}

variable "tenant_table_arn" {
  description = "ARN of the tenant DynamoDB table - locationCount is incremented against the plan's maxLocations in the same transaction as the new location"
  type        = string
  sensitive   = false
}
