variable "environment" {
  description = "The environment to deploy to (dev or prod)"
  type        = string
  sensitive   = false
}

variable "reactivate_menu_item_lambda_arn" {
  description = "ARN of the reactivate-menu-item Lambda function this role is allowed to invoke"
  type        = string
  sensitive   = false
}
