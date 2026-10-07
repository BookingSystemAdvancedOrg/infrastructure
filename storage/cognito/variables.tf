variable "environment" {
  description = "The environment to deploy to (dev or prod)"
  type        = string
  sensitive   = false
}

variable "pre_token_generation_lambda_arn" {
  description = "ARN of the pre-token-generation trigger (compute/lambda/pre-token-generation) that adds tenant_id and role claims"
  type        = string
  sensitive   = false
}

variable "pre_token_generation_function_name" {
  description = "Function name of the pre-token-generation trigger, for the Cognito invoke permission"
  type        = string
  sensitive   = false
}

variable "admin_app_url" {
  description = "URL of the shared restaurant admin app, put into the invitation email"
  type        = string
  sensitive   = false
}

variable "invite_email_subject" {
  description = "Subject of the email a new owner/staff member gets with their temporary password"
  type        = string
  sensitive   = false
  default     = "Ditt konto till restaurangens adminpanel"
}

variable "invite_email_message" {
  description = "Body of the invitation email. Must contain {username} and {####} (Cognito fills those in); $${admin_app_url} is replaced with var.admin_app_url."
  type        = string
  sensitive   = false
  default     = "Hej!<br><br>Du har fått ett konto i restaurangens adminpanel.<br>Logga in på <a href=\"$${admin_app_url}\">$${admin_app_url}</a> med e-postadressen {username} och det tillfälliga lösenordet <b>{####}</b>.<br>Du väljer ett eget lösenord vid första inloggningen."

  validation {
    condition     = strcontains(var.invite_email_message, "{username}") && strcontains(var.invite_email_message, "{####}")
    error_message = "invite_email_message must contain both {username} and {####}."
  }
}

variable "invites_via_ses" {
  description = "Send invitation/reset emails through SES (DEVELOPER) instead of Cognito's capped built-in sender"
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

variable "invite_from_address" {
  description = "From address for invitation emails when invites_via_ses is true, e.g. Plattformen <noreply@mail.example.se>"
  type        = string
  sensitive   = false
  default     = ""
}

variable "lambda_alias_name" {
  description = "Alias every Lambda is invoked through (compute/lambda/*/alias.tf) - resource-policy permissions must be granted on it"
  type        = string
  default     = "live"
}
