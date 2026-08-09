variable "environment" {
  description = "The environment to deploy to (dev or prod)"
  type        = string
  sensitive   = false
}

variable "role_arn" {
  description = "ARN of the ManageMenuFn execution role (security/iam/manage-menu)"
  type        = string
  sensitive   = true
}

variable "ecr_repository_url" {
  description = "Repository URL of the ManageMenuFn ECR repository (storage/ecr/manage-menu) — the repo itself is owned there, not created in this module"
  type        = string
  sensitive   = true
}

variable "menu_table_name" {
  description = "Name of the menu DynamoDB table, passed as an environment variable for the handler's SDK calls"
  type        = string
  sensitive   = false
}

variable "region" {
  description = "AWS region this Lambda's log group, ECR repository, and image push target live in"
  type        = string
  sensitive   = false
}
