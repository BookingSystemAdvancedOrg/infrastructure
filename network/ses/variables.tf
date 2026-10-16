variable "no_reply_email_address" {
  description = "No-reply sender address (no mailbox needed) - its domain becomes the SES identity"
  type        = string
  sensitive   = false

  validation {
    condition     = can(regex("^[^@\\s]+@[^@\\s]+\\.[^@\\s]+$", var.no_reply_email_address))
    error_message = "no_reply_email_address must be an email address like noreply@example.se."
  }
}
