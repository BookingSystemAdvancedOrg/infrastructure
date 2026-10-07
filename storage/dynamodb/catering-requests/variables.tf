variable "environment" {
  description = "The environment to deploy to (dev or prod)"
  type        = string
  sensitive   = false
}

variable "notification_lambda_arn" {
  description = "ARN of the NotificationFn Lambda function — invoked off this table's stream for new requests and customer-facing status changes"
  type        = string
  sensitive   = false
}

variable "notification_dlq_arn" {
  description = "ARN of the SQS queue that receives stream batches NotificationFn failed to process after all retries"
  type        = string
  sensitive   = false
}

variable "lifecycle_lambda_arn" {
  description = "ARN of the catering-lifecycle Lambda function — invoked off this table's stream on every write to a request head item"
  type        = string
  sensitive   = false
}

variable "lifecycle_dlq_arn" {
  description = "ARN of the SQS queue that receives stream batches catering-lifecycle failed to process after all retries"
  type        = string
  sensitive   = false
}
