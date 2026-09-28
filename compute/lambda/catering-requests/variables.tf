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
  description = "ECR repository URL for the catering-requests container image"
  type        = string
  sensitive   = true
}

variable "catering_requests_table_name" {
  description = "Name of the catering-requests DynamoDB table"
  type        = string
  sensitive   = false
}

variable "location_table_name" {
  description = "Name of the location DynamoDB table — used to validate location and read catering settings at request time"
  type        = string
  sensitive   = false
}

variable "catering_discount_tiers_table_name" {
  description = "Name of the catering-discount-tiers DynamoDB table — used to calculate volume discounts at submission time"
  type        = string
  sensitive   = false
}

variable "menu_table_name" {
  description = "Name of the menu DynamoDB table — used to validate line items and capture price snapshots"
  type        = string
  sensitive   = false
}

variable "region" {
  description = "AWS region — passed to the function as an environment variable"
  type        = string
  sensitive   = false
}
