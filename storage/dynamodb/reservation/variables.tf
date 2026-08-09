variable "environment" {
  description = "The environment to deploy to (dev or prod)"
  type        = string
  sensitive   = false
}

variable "notification_lambda_arn" {
  description = "ARN of the NotificationFn Lambda function — invoked off this table's stream when a reservation's status changes to \"reserved\""
  type        = string
  sensitive   = false
}
