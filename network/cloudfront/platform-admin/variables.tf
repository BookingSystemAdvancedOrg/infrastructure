variable "environment" {
  description = "The environment to deploy to (dev or prod)"
  type        = string
  sensitive   = false
}

variable "bucket_regional_domain_name" {
  description = "Regional domain name of the platform admin front-end asset bucket (storage/s3/platform-admin-front-end-asset)"
  type        = string
  sensitive   = false
}

variable "aliases" {
  description = "Custom hostnames (ops.<platform domain>); empty until the platform domain is set"
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
