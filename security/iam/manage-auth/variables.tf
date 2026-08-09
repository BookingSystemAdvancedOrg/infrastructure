variable "environment" {
  description = "The environment to deploy to (dev or prod)"
  type        = string
  sensitive   = false
}

variable "user_pool_arn" {
  description = "ARN of the staff/owner/super-user Cognito User Pool — the only resource this role is allowed to act against"
  type        = string
  sensitive   = false
}

variable "region" {
  description = "AWS region this Lambda's log group lives in"
  type        = string
  sensitive   = false
}
