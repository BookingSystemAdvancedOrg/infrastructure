variable "environment" {
  description = "The environment to deploy to (dev or prod)"
  type        = string
  sensitive   = false
}

variable "finance_rollup_lambda_arn" {
  description = "ARN of the finance-rollup Lambda function this role is allowed to invoke"
  type        = string
  sensitive   = false
}
