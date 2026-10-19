variable "environment" {
  description = "The environment to deploy to (dev or prod)"
  type        = string
  sensitive   = false
}

variable "role_arn" {
  description = "ARN of the ManageAuthFn execution role (security/iam/manage-auth)"
  type        = string
  sensitive   = true
}

variable "ecr_repository_url" {
  description = "Repository URL of the ManageAuthFn ECR repository (storage/ecr/manage-auth) - the repo itself is owned there, not created in this module"
  type        = string
  sensitive   = true
}

variable "cognito_user_pool_id" {
  description = "ID of the Cognito user pool, passed as an environment variable for the handler's SDK calls"
  type        = string
  sensitive   = false
}

variable "cognito_client_id" {
  description = "ID of the Cognito user pool app client, passed as an environment variable for the handler's SDK calls"
  type        = string
  sensitive   = false
}

variable "cognito_client_secret" {
  description = "Secret of the Cognito user pool app client, passed as an environment variable for the handler's SDK calls (required for SECRET_HASH once the client has a secret)"
  type        = string
  sensitive   = true
}

variable "region" {
  description = "AWS region this Lambda's log group, ECR repository, and image push target live in"
  type        = string
  sensitive   = false
}

variable "request_guard_table_name" {
  description = "Name of the request-guard table - per-IP limits on the forgot/reset password routes"
  type        = string
  sensitive   = false
}

variable "cloudfront_edge_secret" {
  description = "Shared secret from the admin app's CloudFront (x-booqy-edge); lets the function trust the viewer IP/host headers"
  type        = string
  sensitive   = true
}

variable "refresh_cookie_max_age" {
  description = "Lifetime of the refresh token cookie in seconds; equal to the app client's refresh token validity"
  type        = number
  sensitive   = false
}

variable "cookie_allowed_origins" {
  description = "Extra origins (comma-separated) allowed to use the cookie routes, for local development; empty in prod"
  type        = string
  sensitive   = false
  default     = ""
}
