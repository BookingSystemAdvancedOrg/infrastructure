variable "environment" {
  description = "The environment to deploy to (dev or prod)"
  type        = string
  sensitive   = false
}

variable "role_arn" {
  description = "ARN of the guest-privacy execution role (security/iam/guest-privacy)"
  type        = string
  sensitive   = true
}

variable "ecr_repository_url" {
  description = "Repository URL of the guest-privacy ECR repository (storage/ecr/guest-privacy)"
  type        = string
  sensitive   = true
}

variable "retention_env" {
  description = "RETENTION_* environment variables (the periods the notice template shows)"
  type        = map(string)
  sensitive   = false
}

variable "tenant_table_name" {
  type = string
}

variable "location_table_name" {
  type = string
}

variable "location_id_index_name" {
  type = string
}

variable "user_table_name" {
  type = string
}

variable "consent_table_name" {
  type = string
}

variable "marketing_table_name" {
  type = string
}

variable "reservation_table_name" {
  type = string
}

variable "order_table_name" {
  type = string
}

variable "catering_requests_table_name" {
  type = string
}
