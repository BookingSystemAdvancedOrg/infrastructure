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
  description = "*.cloudfront.net domain of the restaurant admin app distribution (alias target for admin_app_hostname)"
  type        = string
  sensitive   = false
}

variable "platform_admin_distribution_domain_name" {
  description = "*.cloudfront.net domain of the platform admin app distribution (alias target for platform_admin_hostname)"
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

variable "subdomain_delegations" {
  description = "label => name servers of a zone in another account that answers <label>.<platform_domain> (prod: dev)"
  type        = map(list(string))
  sensitive   = false
  default     = {}
}

variable "tenant_sites_enabled" {
  description = "Create the restaurant website hosting: tenant-sites bucket, multi-tenant distribution, connection group and the *.<domain> record"
  type        = bool
  sensitive   = false
  default     = false
}

variable "admin_app_hostname" {
  description = "Hostname of the restaurant admin app (admin-front-end), e.g. restaurant.booqy.se"
  type        = string
  sensitive   = false
}

variable "platform_admin_hostname" {
  description = "Hostname of the operator app (Booqy Console), e.g. admin.booqy.se"
  type        = string
  sensitive   = false
}

variable "landing_contact_email" {
  description = "Contact address shown on the public page on <domain> (also for privacy questions)"
  type        = string
  sensitive   = false
}

variable "landing_company" {
  description = "Company named as the operator of Booqy on the public page"
  type        = string
  sensitive   = false
}

variable "landing_updated" {
  description = "'Senast uppdaterad' date on the privacy policy and terms, e.g. 16 oktober 2026 (its last four characters are the footer year)"
  type        = string
  sensitive   = false
}
