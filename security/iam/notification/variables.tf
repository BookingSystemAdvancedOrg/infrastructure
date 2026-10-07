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

variable "order_stream_arn" {
  description = "ARN of the order DynamoDB table's Stream — read-only, for the paid/failed payment-outcome notifications"
  type        = string
  sensitive   = false
}

variable "catering_requests_stream_arn" {
  description = "ARN of the catering-requests DynamoDB table's Stream — read-only, for the new-request owner email and customer-facing status emails"
  type        = string
  sensitive   = false
}

variable "notification_dlq_arn" {
  description = "ARN of the notification-stream DLQ - all three stream mappings (reservation, order, catering-requests) send failed batches there"
  type        = string
  sensitive   = false
}

variable "catering_link_signing_key_secret_arn" {
  description = "ARN of the catering magic-link HMAC key secret — read to build customer links in catering emails"
  type        = string
  sensitive   = false
}
