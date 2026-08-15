variable "no_reply_email_address" {
  description = "Email address to verify as an SES identity for sending no-reply emails"
  type        = string
  sensitive   = false
}
