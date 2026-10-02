variable "environment" {
  description = "The environment to deploy to (dev or prod)"
  type        = string
  sensitive   = false
}

variable "role_arn" {
  description = "ARN of the ReactivateMenuItemFn execution role (security/iam/reactivate-menu-item)"
  type        = string
  sensitive   = true
}

variable "ecr_repository_url" {
  description = "Repository URL of the ReactivateMenuItemFn ECR repository (storage/ecr/reactivate-menu-item) — the repo itself is owned there, not created in this module"
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
