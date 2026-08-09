variable "environment" {
  description = "The environment to deploy to (dev or prod)"
  type        = string
  sensitive   = false
}

variable "admin_bucket_regional_domain_name" {
  description = "Regional domain name of the admin front-end asset S3 bucket (storage/s3/admin-front-end-asset) - this distribution's default origin"
  type        = string
  sensitive   = false
}

variable "menu_image_bucket_regional_domain_name" {
  description = "Regional domain name of the menu-image S3 bucket (storage/s3/menu-image) - this distribution's /menu-images/* origin"
  type        = string
  sensitive   = false
}
