variable "environment" {
  description = "The environment to deploy to (dev or prod)"
  type        = string
  sensitive   = false
}

variable "catering_discount_tiers_table_arn" {
  description = "ARN of the catering-discount-tiers DynamoDB table — this role has full CRUD access to it"
  type        = string
  sensitive   = false
}

variable "region" {
  description = "AWS region this Lambda's log group lives in"
  type        = string
  sensitive   = false
}
