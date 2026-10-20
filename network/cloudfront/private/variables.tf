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

variable "canonical_host" {
  description = "The admin app's own hostname (restaurang.<platform domain>); requests for a legacy_hosts name are redirected here. Empty = no redirect"
  type        = string
  sensitive   = false
  default     = ""
}

variable "legacy_hosts" {
  description = "Old hostnames still served by this distribution only to redirect (301) to canonical_host - e.g. restaurant.<platform domain>"
  type        = list(string)
  sensitive   = false
  default     = []
}

variable "aliases" {
  description = "Custom hostnames for this distribution (restaurang.<platform domain> plus the legacy restaurant. name); empty until the platform domain is set"
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

variable "api_origin_domain" {
  description = "Host of API Gateway's default endpoint (<api id>.execute-api.<region>.amazonaws.com), served under /api on this distribution"
  type        = string
  sensitive   = false
}

variable "edge_secret" {
  description = "Value of the x-booqy-edge origin header; the API trusts the viewer IP/host headers only with it"
  type        = string
  sensitive   = true
}
