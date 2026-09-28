variable "environment" {
  description = "The environment to deploy to (dev or prod)"
  type        = string
  sensitive   = false
}

variable "role_arn" {
  description = "ARN of the IAM execution role for this Lambda"
  type        = string
  sensitive   = true
}

variable "ecr_repository_url" {
  description = "ECR repository URL for the catering-discount-tiers container image"
  type        = string
  sensitive   = true
}

variable "catering_discount_tiers_table_name" {
  description = "Name of the catering-discount-tiers DynamoDB table"
  type        = string
  sensitive   = false
}

variable "region" {
  description = "AWS region — passed to the function as an environment variable"
  type        = string
  sensitive   = false
}
