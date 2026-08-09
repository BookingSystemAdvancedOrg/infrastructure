variable "environment" {
  description = "The environment to deploy to (dev or prod)"
  type        = string
  sensitive   = false
}

variable "role_arn" {
  description = "ARN of the ActivateLayoutVersionFn execution role (security/iam/activate-layout-version)"
  type        = string
  sensitive   = true
}

variable "ecr_repository_url" {
  description = "Repository URL of the ActivateLayoutVersionFn ECR repository (storage/ecr/activate-layout-version) — the repo itself is owned there, not created in this module"
  type        = string
  sensitive   = true
}

variable "published_layout_snapshot_table_name" {
  description = "Name of the published layout snapshot DynamoDB table, passed as an environment variable for the handler's SDK calls"
  type        = string
  sensitive   = false
}

variable "scheduler_invoke_role_arn" {
  description = "ARN of the IAM role handed to EventBridge Scheduler when creating an expire-layout-version schedule, passed as an environment variable for the handler's SDK calls"
  type        = string
  sensitive   = true
}

variable "expire_layout_version_function_arn" {
  description = "ARN of the ExpireLayoutVersionFn Lambda — the Scheduler target for the expire-layout-version schedule, passed as an environment variable for the handler's SDK calls"
  type        = string
  sensitive   = false
}

variable "region" {
  description = "AWS region this Lambda's log group, ECR repository, and image push target live in"
  type        = string
  sensitive   = false
}
