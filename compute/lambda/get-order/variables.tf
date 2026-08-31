variable "environment" {
  description = "The environment to deploy to (dev or prod)"
  type        = string
  sensitive   = false
}

variable "role_arn" {
  description = "ARN of the GetOrderFn execution role (security/iam/get-order)"
  type        = string
  sensitive   = true
}

variable "ecr_repository_url" {
  description = "Repository URL of the GetOrderFn ECR repository (storage/ecr/get-order) — the repo itself is owned there, not created in this module"
  type        = string
  sensitive   = true
}

variable "order_table_name" {
  description = "Name of the order DynamoDB table, passed as an environment variable for the handler's SDK calls"
  type        = string
  sensitive   = false
}

variable "region" {
  description = "AWS region this Lambda's log group, ECR repository, and image push target live in"
  type        = string
  sensitive   = false
}
