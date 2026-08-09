variable "environment" {
  description = "The environment to deploy to (dev or prod)"
  type        = string
  sensitive   = false
}

variable "role_arn" {
  description = "ARN of the ManageAuthFn execution role (security/iam/manage-auth)"
  type        = string
  sensitive   = true
}

variable "ecr_repository_url" {
  description = "Repository URL of the ManageAuthFn ECR repository (storage/ecr/manage-auth) — the repo itself is owned there, not created in this module"
  type        = string
  sensitive   = true
}

variable "cognito_user_pool_id" {
  description = "ID of the Cognito user pool, passed as an environment variable for the handler's SDK calls"
  type        = string
  sensitive   = false
}

variable "cognito_client_id" {
  description = "ID of the Cognito user pool app client, passed as an environment variable for the handler's SDK calls"
  type        = string
  sensitive   = false
}

variable "region" {
  description = "AWS region this Lambda's log group, ECR repository, and image push target live in"
  type        = string
  sensitive   = false
}
