variable "environment" {
  description = "The environment to deploy to (dev or prod)"
  type        = string
  sensitive   = false
}

variable "name" {
  description = "Function name without the environment prefix, e.g. tenant-custom-message"
  type        = string
  sensitive   = false
}

variable "role_arn" {
  description = "ARN of this function's execution role (security/iam/cognito-custom-message)"
  type        = string
  sensitive   = true
}

variable "reset_url" {
  description = "Absolute URL of the app page that sets the new password (no trailing slash) - the email links to <reset_url>#code=...&email=..."
  type        = string
  sensitive   = false

  validation {
    condition     = can(regex("^https?://[^#?]+$", var.reset_url))
    error_message = "reset_url must be an absolute http(s) URL without a query or fragment."
  }
}

variable "language" {
  description = "Language of the email: sv (restaurant admin app) or en (SBS Admin)"
  type        = string
  sensitive   = false

  validation {
    condition     = contains(["sv", "en"], var.language)
    error_message = "language must be sv or en."
  }
}
