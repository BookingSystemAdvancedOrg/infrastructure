variable "environment" {
  description = "The environment to deploy to (dev or prod)"
  type        = string
  sensitive   = false
}

variable "role_arn" {
  description = "ARN of the PreSignedURLFn execution role (security/iam/pre-signed-url)"
  type        = string
  sensitive   = true
}

variable "ecr_repository_url" {
  description = "Repository URL of the PreSignedURLFn ECR repository (storage/ecr/pre-signed-url) — the repo itself is owned there, not created in this module"
  type        = string
  sensitive   = true
}

variable "menu_images_bucket_name" {
  description = "Name of the MenuImages S3 bucket, passed as an environment variable for the handler's SDK calls"
  type        = string
  sensitive   = false
}

variable "region" {
  description = "AWS region this Lambda's log group, ECR repository, and image push target live in"
  type        = string
  sensitive   = false
}
