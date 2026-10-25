variable "environment" {
  description = "The environment to deploy to (dev or prod)"
  type        = string
  sensitive   = false
}

variable "insights_rollup_lambda_arn" {
  description = "ARN of the insights-rollup Lambda function this role is allowed to invoke"
  type        = string
  sensitive   = false
}
