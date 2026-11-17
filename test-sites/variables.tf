variable "environment" {
  description = "The environment (dev only: the root never creates this module in prod)"
  type        = string

  validation {
    condition     = var.environment != "prod"
    error_message = "Test sites exist only outside prod."
  }
}

variable "main_domain" {
  description = "Zone of the main branch's test hosts (<slug>.test.booqy.se)"
  type        = string
}

variable "dev_domain" {
  description = "Zone of the dev branch's test hosts (<slug>.test-dev.booqy.se)"
  type        = string
}

variable "enabled" {
  description = "Phase 2: certificate, sandbox bucket, the standard distribution with its host router (CloudFront Function and key value store), DNS wildcards and deploy boundary. Off: the zones only (phase 1, until prod delegates them)."
  type        = bool
  default     = false
}

variable "menu_image_bucket_regional_domain_name" {
  description = "Menu image bucket (origin of /menu-images/*); its policy admits this distribution (root config.tf)"
  type        = string
}

variable "web_acl_arn" {
  description = "AWS WAF (v2, CLOUDFRONT scope) web ACL for the sandbox (network/waf-sites); empty for none"
  type        = string
  sensitive   = false
  default     = ""
}

variable "api_origin_domain" {
  description = "Host name of the HTTP API (execute-api) that /api/* forwards to; empty for no /api/*"
  type        = string
  sensitive   = false
  default     = ""
}

variable "waf_edge_secret" {
  description = "Shared secret sent to the API as x-booqy-waf: the request passed the sites' web ACL (bot check)"
  type        = string
  sensitive   = true
  default     = ""
}
