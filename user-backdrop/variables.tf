variable "environment" {
  description = "The environment to deploy to (dev or prod)"
  type        = string
  sensitive   = false
}

variable "region" {
  type = string
}

variable "ecr_repository_url" {
  type = string
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

variable "bucket_name" {
  description = "The user-backdrops bucket (storage/s3/user-backdrops)"
  type        = string
}

variable "bucket_arn" {
  type = string
}

variable "alert_topic_arn" {
  type = string
}

variable "table_name" {
  description = "The user-backdrops table (storage/dynamodb/user-backdrops)"
  type        = string
}

variable "table_arn" {
  type = string
}
