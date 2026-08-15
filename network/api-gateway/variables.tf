variable "environment" {
  description = "The environment to deploy to (dev or prod)"
  type        = string
  sensitive   = false
}

variable "region" {
  description = "AWS region this API Gateway and its Cognito user pool live in - used to build the JWT authorizer's issuer URL"
  type        = string
  sensitive   = false
}

variable "cognito_user_pool_id" {
  description = "ID of the Cognito user pool whose tokens the JWT authorizer accepts"
  type        = string
  sensitive   = true
}

variable "cognito_client_id" {
  description = "ID of the Cognito app client - set as the JWT authorizer's audience, so tokens issued for a different client are rejected"
  type        = string
  sensitive   = true
}

variable "allowed_origins" {
  description = "Front-end origin(s) allowed to call this API cross-origin, e.g. [\"https://app.example.com\"]"
  type        = list(string)
  sensitive   = false
}

variable "get_location_function_name" {
  description = "Name of the get-location Lambda (compute/lambda/get-location) - granted permission to be invoked by this API"
  type        = string
  sensitive   = false
}

variable "get_location_invoke_arn" {
  description = "Invoke ARN of the get-location Lambda (compute/lambda/get-location) - the integration target for its route"
  type        = string
  sensitive   = true
}

variable "create_location_function_name" {
  description = "Name of the create-location Lambda (compute/lambda/create-location) - granted permission to be invoked by this API"
  type        = string
  sensitive   = false
}

variable "create_location_invoke_arn" {
  description = "Invoke ARN of the create-location Lambda (compute/lambda/create-location) - the integration target for its route"
  type        = string
  sensitive   = true
}

variable "get_menu_function_name" {
  description = "Name of the get-menu Lambda (compute/lambda/get-menu) - granted permission to be invoked by this API"
  type        = string
  sensitive   = false
}

variable "get_menu_invoke_arn" {
  description = "Invoke ARN of the get-menu Lambda (compute/lambda/get-menu) - the integration target for its route"
  type        = string
  sensitive   = true
}

variable "manage_menu_function_name" {
  description = "Name of the manage-menu Lambda (compute/lambda/manage-menu) - granted permission to be invoked by this API"
  type        = string
  sensitive   = false
}

variable "manage_menu_invoke_arn" {
  description = "Invoke ARN of the manage-menu Lambda (compute/lambda/manage-menu) - the integration target for its route"
  type        = string
  sensitive   = true
}

variable "get_availability_function_name" {
  description = "Name of the get-availability Lambda (compute/lambda/get-availability) - granted permission to be invoked by this API"
  type        = string
  sensitive   = false
}

variable "get_availability_invoke_arn" {
  description = "Invoke ARN of the get-availability Lambda (compute/lambda/get-availability) - the integration target for its route"
  type        = string
  sensitive   = true
}

variable "create_pending_reservation_function_name" {
  description = "Name of the create-pending-reservation Lambda (compute/lambda/create-pending-reservation) - granted permission to be invoked by this API"
  type        = string
  sensitive   = false
}

variable "create_pending_reservation_invoke_arn" {
  description = "Invoke ARN of the create-pending-reservation Lambda (compute/lambda/create-pending-reservation) - the integration target for its route"
  type        = string
  sensitive   = true
}

variable "get_reservation_function_name" {
  description = "Name of the get-reservation Lambda (compute/lambda/get-reservation) - granted permission to be invoked by this API"
  type        = string
  sensitive   = false
}

variable "get_reservation_invoke_arn" {
  description = "Invoke ARN of the get-reservation Lambda (compute/lambda/get-reservation) - the integration target for its route"
  type        = string
  sensitive   = true
}

variable "cancel_reservation_function_name" {
  description = "Name of the cancel-reservation Lambda (compute/lambda/cancel-reservation) - granted permission to be invoked by this API"
  type        = string
  sensitive   = false
}

variable "cancel_reservation_invoke_arn" {
  description = "Invoke ARN of the cancel-reservation Lambda (compute/lambda/cancel-reservation) - the integration target for its route"
  type        = string
  sensitive   = true
}

variable "mark_arrived_function_name" {
  description = "Name of the mark-arrived Lambda (compute/lambda/mark-arrived) - granted permission to be invoked by this API"
  type        = string
  sensitive   = false
}

variable "mark_arrived_invoke_arn" {
  description = "Invoke ARN of the mark-arrived Lambda (compute/lambda/mark-arrived) - the integration target for its route"
  type        = string
  sensitive   = true
}

variable "block_table_function_name" {
  description = "Name of the block-table Lambda (compute/lambda/block-table) - granted permission to be invoked by this API"
  type        = string
  sensitive   = false
}

variable "block_table_invoke_arn" {
  description = "Invoke ARN of the block-table Lambda (compute/lambda/block-table) - the integration target for its route"
  type        = string
  sensitive   = true
}

variable "manage_layout_element_function_name" {
  description = "Name of the manage-layout-element Lambda (compute/lambda/manage-layout-element) - granted permission to be invoked by this API"
  type        = string
  sensitive   = false
}

variable "manage_layout_element_invoke_arn" {
  description = "Invoke ARN of the manage-layout-element Lambda (compute/lambda/manage-layout-element) - the integration target for its route"
  type        = string
  sensitive   = true
}

variable "publish_layout_function_name" {
  description = "Name of the publish-layout Lambda (compute/lambda/publish-layout) - granted permission to be invoked by this API"
  type        = string
  sensitive   = false
}

variable "publish_layout_invoke_arn" {
  description = "Invoke ARN of the publish-layout Lambda (compute/lambda/publish-layout) - the integration target for its route"
  type        = string
  sensitive   = true
}

variable "list_layout_version_function_name" {
  description = "Name of the list-layout-version Lambda (compute/lambda/list-layout-version) - granted permission to be invoked by this API"
  type        = string
  sensitive   = false
}

variable "list_layout_version_invoke_arn" {
  description = "Invoke ARN of the list-layout-version Lambda (compute/lambda/list-layout-version) - the integration target for its route"
  type        = string
  sensitive   = true
}

variable "activate_layout_version_function_name" {
  description = "Name of the activate-layout-version Lambda (compute/lambda/activate-layout-version) - granted permission to be invoked by this API"
  type        = string
  sensitive   = false
}

variable "activate_layout_version_invoke_arn" {
  description = "Invoke ARN of the activate-layout-version Lambda (compute/lambda/activate-layout-version) - the integration target for its route"
  type        = string
  sensitive   = true
}

variable "manage_auth_function_name" {
  description = "Name of the manage-auth Lambda (compute/lambda/manage-auth) - granted permission to be invoked by this API"
  type        = string
  sensitive   = false
}

variable "manage_auth_invoke_arn" {
  description = "Invoke ARN of the manage-auth Lambda (compute/lambda/manage-auth) - the integration target for its route"
  type        = string
  sensitive   = true
}

variable "manage_user_function_name" {
  description = "Name of the manage-user Lambda (compute/lambda/manage-user) - granted permission to be invoked by this API"
  type        = string
  sensitive   = false
}

variable "manage_user_invoke_arn" {
  description = "Invoke ARN of the manage-user Lambda (compute/lambda/manage-user) - the integration target for its route"
  type        = string
  sensitive   = true
}

variable "pre_signed_url_function_name" {
  description = "Name of the pre-signed-url Lambda (compute/lambda/pre-signed-url) - granted permission to be invoked by this API"
  type        = string
  sensitive   = false
}

variable "pre_signed_url_invoke_arn" {
  description = "Invoke ARN of the pre-signed-url Lambda (compute/lambda/pre-signed-url) - the integration target for its route"
  type        = string
  sensitive   = true
}
