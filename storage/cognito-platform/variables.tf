variable "environment" {
  description = "The environment to deploy to (dev or prod)"
  type        = string
  sensitive   = false
}

variable "operator_emails" {
  description = "Platform operators to create in this pool (each gets an emailed temporary password and must enroll TOTP MFA)"
  type        = list(string)
  sensitive   = false
}

variable "app_urls" {
  description = "Origins the platform admin app is served from (no trailing slash) - each gets <url>/auth/callback as an OAuth redirect"
  type        = list(string)
  sensitive   = false
}
