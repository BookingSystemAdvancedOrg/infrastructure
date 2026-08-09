variable "environment" {
  description = "The environment to deploy to (dev or prod)"
  type        = string
  sensitive   = false
}

variable "role_arn" {
  description = "ARN of the ListLayoutVersionFn execution role (security/iam/list-layout-version)"
  type        = string
  sensitive   = true
}

variable "ecr_repository_url" {
  description = "Repository URL of the ListLayoutVersionFn ECR repository (storage/ecr/list-layout-version) — the repo itself is owned there, not created in this module"
  type        = string
  sensitive   = true
}

variable "published_layout_snapshot_table_name" {
  description = "Name of the published layout snapshot DynamoDB table, passed as an environment variable for the handler's SDK calls"
  type        = string
  sensitive   = false
}

variable "region" {
  description = "AWS region this Lambda's log group, ECR repository, and image push target live in"
  type        = string
  sensitive   = false
}
