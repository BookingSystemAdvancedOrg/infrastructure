variable "environment" {
  description = "The environment to deploy to (dev or prod)"
  type        = string
  sensitive   = false
}

variable "platform_tenants_lambda_arn" {
  description = "ARN of the platform-tenants Lambda function this role is allowed to invoke"
  type        = string
  sensitive   = false
}
