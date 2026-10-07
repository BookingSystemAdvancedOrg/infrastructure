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

variable "aliases" {
  description = "Custom hostnames for this distribution (app.<platform domain>); empty until the platform domain is set"
  type        = list(string)
  sensitive   = false
  default     = []
}

variable "acm_certificate_arn" {
  description = "us-east-1 ACM certificate covering the aliases; empty = default *.cloudfront.net certificate"
  type        = string
  sensitive   = false
  default     = ""
}
