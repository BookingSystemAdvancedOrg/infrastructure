variable "environment" {
  description = "The environment to deploy to (dev or prod)"
  type        = string
  sensitive   = false
}

variable "order_table_arn" {
  description = "ARN of the order DynamoDB table — the only resource this role is allowed to access"
  type        = string
  sensitive   = false
}

variable "region" {
  description = "AWS region this Lambda's log group lives in"
  type        = string
  sensitive   = false
}
