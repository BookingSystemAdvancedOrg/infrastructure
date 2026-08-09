variable "environment" {
  description = "The environment to deploy to (dev or prod)"
  type        = string
  sensitive   = false
}

variable "role_arn" {
  description = "ARN of the ManageUserFn execution role (security/iam/manage-user)"
  type        = string
  sensitive   = true
}

variable "ecr_repository_url" {
  description = "Repository URL of the ManageUserFn ECR repository (storage/ecr/manage-user) — the repo itself is owned there, not created in this module"
  type        = string
  sensitive   = true
}

variable "user_table_name" {
  description = "Name of the user DynamoDB table, passed as an environment variable for the handler's SDK calls"
  type        = string
  sensitive   = false
}

variable "cognito_user_pool_id" {
  description = "ID of the Cognito user pool, passed as an environment variable for the handler's SDK calls"
  type        = string
  sensitive   = false
}

variable "region" {
  description = "AWS region this Lambda's log group, ECR repository, and image push target live in"
  type        = string
  sensitive   = false
}
