variable "environment" {
  description = "The environment to deploy to (dev or prod)"
  type        = string
  sensitive   = false
}

variable "reservation_reminders_lambda_arn" {
  description = "ARN of the reservation-reminders Lambda function this role is allowed to invoke"
  type        = string
  sensitive   = false
}
