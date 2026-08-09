variable "environment" {
  description = "The environment to deploy to (dev or prod)"
  type        = string
  sensitive   = false
}

variable "role_arn" {
  description = "ARN of the NotificationFn execution role (security/iam/notification)"
  type        = string
  sensitive   = true
}

variable "ecr_repository_url" {
  description = "Repository URL of the NotificationFn ECR repository (storage/ecr/notification) — the repo itself is owned there, not created in this module"
  type        = string
  sensitive   = true
}

variable "no_reply_email_address" {
  description = "No-reply email address used as the SES 'from' address, passed as an environment variable for the handler's SDK calls"
  type        = string
  sensitive   = false
}

variable "region" {
  description = "AWS region this Lambda's log group, ECR repository, and image push target live in"
  type        = string
  sensitive   = false
}
