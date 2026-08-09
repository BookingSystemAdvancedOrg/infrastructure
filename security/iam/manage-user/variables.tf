variable "environment" {
  description = "The environment to deploy to (dev or prod)"
  type        = string
  sensitive   = false
}

variable "user_table_arn" {
  description = "ARN of the user DynamoDB table — the only resource this role is allowed to access"
  type        = string
  sensitive   = false
}

variable "user_pool_arn" {
  description = "ARN of the staff/owner/super-user Cognito User Pool — scoped Admin* user-management access"
  type        = string
  sensitive   = false
}

variable "region" {
  description = "AWS region this Lambda's log group lives in"
  type        = string
  sensitive   = false
}
