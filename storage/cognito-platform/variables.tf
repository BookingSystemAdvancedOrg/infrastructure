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

variable "invites_via_ses" {
  description = "Send this pool's emails (invitations, password resets) through SES (DEVELOPER) instead of Cognito's capped built-in sender - the same switch as the tenant pool"
  type        = bool
  sensitive   = false
  default     = false
}

variable "ses_identity_arn" {
  description = "ARN of the verified SES identity Cognito sends from when invites_via_ses is true"
  type        = string
  sensitive   = false
  default     = ""
}

variable "from_address" {
  description = "From address of this pool's emails when invites_via_ses is true"
  type        = string
  sensitive   = false
  default     = ""
}

variable "custom_message_lambda_arn" {
  description = "Alias ARN of the custom message trigger that makes the forgot-password email a link - attached only when invites_via_ses is true"
  type        = string
  sensitive   = false
}

variable "custom_message_function_name" {
  description = "Function name of the custom message trigger, for the Cognito invoke permission"
  type        = string
  sensitive   = false
}

variable "lambda_alias_name" {
  description = "Alias every Lambda is invoked through - resource-policy permissions must be granted on it"
  type        = string
  default     = "live"
}
