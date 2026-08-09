variable "environment" {
  description = "The environment to deploy to (dev or prod)"
  type        = string
  sensitive   = false
}

variable "expire_layout_version_lambda_arn" {
  description = "ARN of the expire-layout-version Lambda function this role is allowed to invoke"
  type        = string
  sensitive   = false
}
