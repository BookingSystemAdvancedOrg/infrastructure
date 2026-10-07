variable "environment" {
  description = "The environment to deploy to (dev or prod)"
  type        = string
  sensitive   = false
}

variable "platform_domain" {
  description = "Domain the platform owns, e.g. bokning.example.se"
  type        = string
  sensitive   = false
}

variable "menu_image_bucket_regional_domain_name" {
  description = "Regional domain name of the menu-image bucket - served at /menu-images/* on tenant sites"
  type        = string
  sensitive   = false
}

variable "admin_distribution_domain_name" {
  description = "*.cloudfront.net domain of the restaurant admin app distribution (alias target for app.<domain>)"
  type        = string
  sensitive   = false
}

variable "platform_admin_distribution_domain_name" {
  description = "*.cloudfront.net domain of the platform admin app distribution (alias target for ops.<domain>)"
  type        = string
  sensitive   = false
}

variable "site_placeholder_key" {
  description = "Key of the 'coming soon' page in the tenant-sites bucket"
  type        = string
  sensitive   = false
  default     = "_placeholder/index.html"
}

variable "web_acl_arn" {
  description = "Optional AWS WAF (v2, CLOUDFRONT scope) web ACL for the tenant sites; empty for none"
  type        = string
  sensitive   = false
  default     = ""
}
