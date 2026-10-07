variable "environment" {
  description = "The environment to deploy to (dev or prod)"
  type        = string
  sensitive   = false
}

variable "catering_lifecycle_lambda_arn" {
  description = "ARN of the catering-lifecycle Lambda function this role is allowed to invoke"
  type        = string
  sensitive   = false
}

variable "scheduler_dlq_arn" {
  description = "ARN of the SQS DLQ catering schedules deliver to when every retry of the target invocation fails"
  type        = string
  sensitive   = false
}
