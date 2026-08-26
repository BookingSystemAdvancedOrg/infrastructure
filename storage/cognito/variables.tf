variable "environment" {
  description = "The environment to deploy to (dev or prod)"
  type        = string
  sensitive   = false
}

variable "super_admin_emails" {
  description = "Emails of the bootstrap super_user accounts to create in this pool. Membership is reconciled on every apply - remove an email here to remove that person from super_user, but the Cognito user itself is only created, never deleted, by this list."
  type        = list(string)
  sensitive   = false

  validation {
    condition     = length(var.super_admin_emails) > 0
    error_message = "At least one super_admin_emails entry is required - a pool must never be left with zero super_user accounts."
  }
}

variable "super_admin_temp_password" {
  description = "Shared temporary password (FORCE_CHANGE_PASSWORD) assigned to every account in super_admin_emails at creation. Must satisfy this pool's password_policy (min 8 chars, upper/lower/number/symbol)."
  type        = string
  sensitive   = true
  default     = "Helloworld123!"

  # Terraform's regex() uses RE2 (Go regexp), which has no lookahead
  # support - a single "match all of these classes" pattern like
  # ^(?=.*[a-z])(?=.*[A-Z])...$ silently fails to compile, and can()
  # around a non-compiling regex just returns false unconditionally,
  # rejecting every value including valid ones. Check each character
  # class as its own regex instead.
  validation {
    condition = alltrue([
      length(var.super_admin_temp_password) >= 8,
      can(regex("[a-z]", var.super_admin_temp_password)),
      can(regex("[A-Z]", var.super_admin_temp_password)),
      can(regex("[0-9]", var.super_admin_temp_password)),
      can(regex("[^a-zA-Z0-9]", var.super_admin_temp_password)),
    ])
    error_message = "super_admin_temp_password must be at least 8 characters and include a lowercase letter, an uppercase letter, a number, and a symbol - matching this pool's password_policy."
  }
}
