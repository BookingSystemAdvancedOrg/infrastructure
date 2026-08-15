variable "environment" {
  description = "The environment to deploy to (dev or prod)"
  type        = string
  sensitive   = false
}

variable "no_show_check_lambda_arn" {
  description = "ARN of the no-show-check Lambda function this role is allowed to invoke"
  type        = string
  sensitive   = false
}
