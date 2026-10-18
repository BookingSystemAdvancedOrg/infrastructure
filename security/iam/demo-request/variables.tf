variable "environment" {
  description = "The environment to deploy to (dev or prod)"
  type        = string
  sensitive   = false
}

variable "region" {
  description = "AWS region the function and its log group live in"
  type        = string
  sensitive   = false
}

variable "ses_identity_arn" {
  description = "ARN of the SES identity the sender address belongs to"
  type        = string
  sensitive   = false
}

variable "from_address" {
  description = "The only sender address this role may send from"
  type        = string
  sensitive   = false
}
