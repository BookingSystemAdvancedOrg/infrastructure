variable "environment" {
  description = "The environment to deploy to (dev or prod)"
  type        = string
  sensitive   = false
}

variable "tenant_purge_lambda_arn" {
  description = "ARN of the tenant-purge Lambda function this role is allowed to invoke"
  type        = string
  sensitive   = false
}
