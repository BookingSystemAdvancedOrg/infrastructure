variable "environment" {
  description = "The environment to deploy to (dev or prod)"
  type        = string
  sensitive   = false
}

variable "role_arn" {
  description = "ARN of the demo-request execution role (security/iam/demo-request)"
  type        = string
  sensitive   = true
}

variable "recipient" {
  description = "Address every demo request is emailed to"
  type        = string
  sensitive   = false
}

variable "from_address" {
  description = "Sender address (an address on a verified SES identity) - shown as \"Booqy webbplats\""
  type        = string
  sensitive   = false
}
