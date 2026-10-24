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

variable "customer_bucket_regional_domain_name" {
  description = "Regional domain name of the customer-front-end bucket - the shared restaurant site served on every restaurant domain"
  type        = string
  sensitive   = false
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
  description = "Serve restaurant websites on the restaurants' own domains: multi-tenant distribution and connection group"
  type        = bool
  sensitive   = false
  default     = false
}

variable "tenant_subdomains_enabled" {
  description = "Also serve them on <slug>.<domain> (the *.<domain> record). Needs tenant_sites_enabled"
  type        = bool
  sensitive   = false
  default     = false
}

variable "legacy_admin_app_hostname" {
  description = "The admin app's first hostname, e.g. restaurant.booqy.se - still points at the admin distribution, which redirects it to admin_app_hostname"
  type        = string
  sensitive   = false
}

variable "admin_app_hostname" {
  description = "Hostname of the restaurant admin app (admin-front-end), e.g. restaurang.booqy.se"
  type        = string
  sensitive   = false
}

variable "platform_admin_hostname" {
  description = "Hostname of the operator app (Booqy Console), e.g. admin.booqy.se"
  type        = string
  sensitive   = false
}

variable "demo_request_enabled" {
  description = "Serve <domain>/api/* on the landing distribution from the demo-request Lambda. A plain bool (known at plan time) - the origin domain itself is only known after the function URL exists, so it can't drive count."
  type        = bool
  default     = false
}

variable "demo_request_origin_domain" {
  description = "Host name of the demo-request Lambda's function URL (used when demo_request_enabled)"
  type        = string
  default     = ""
}

variable "site_analytics_enabled" {
  description = "Serve <domain>/api/collect (the site's cookieless statistics) from the site-analytics Lambda. A plain bool for count, like demo_request_enabled."
  type        = bool
  default     = false
}

variable "site_analytics_origin_domain" {
  description = "Host name of the site-analytics Lambda's function URL (used when site_analytics_enabled)"
  type        = string
  default     = ""
}

variable "site_response_headers_policy_id" {
  description = "Security headers policy for the restaurant websites (network/cloudfront/public)"
  type        = string
  sensitive   = false
}

variable "dmarc_report_address" {
  description = "Mailbox for DMARC aggregate reports (rua). Empty = no reports"
  type        = string
  default     = ""
}
