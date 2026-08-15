variable "environment" {
  description = "The environment to deploy to (dev or prod)"
  type        = string
  sensitive   = false
}

variable "reservation_stream_arn" {
  description = "ARN of the reservation DynamoDB table's Stream — full access for this role"
  type        = string
  sensitive   = false
}

variable "ses_identity_arn" {
  description = "ARN of the no-reply SES identity — used for the payment-recovery email on failed-charge statuses"
  type        = string
  sensitive   = false
}

variable "region" {
  description = "AWS region this Lambda's log group lives in"
  type        = string
  sensitive   = false
}
