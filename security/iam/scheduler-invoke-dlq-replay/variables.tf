variable "environment" {
  description = "The environment to deploy to (dev or prod)"
  type        = string
  sensitive   = false
}

variable "dlq_replay_lambda_arn" {
  description = "ARN of the dlq-replay Lambda function this role is allowed to invoke"
  type        = string
  sensitive   = false
}
