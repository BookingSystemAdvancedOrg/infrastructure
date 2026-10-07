variable "environment" {
  description = "The environment to deploy to (dev or prod)"
  type        = string
  sensitive   = false
}

variable "role_arn" {
  description = "ARN of the pre-token-generation execution role (security/iam/pre-token-generation)"
  type        = string
  sensitive   = true
}
