variable "environment" {
  description = "The environment to deploy to (dev or prod)"
  type        = string
  sensitive   = false
}

variable "role_arn" {
  description = "ARN of the CreatePendingReservationFn execution role (security/iam/create-pending-reservation)"
  type        = string
  sensitive   = true
}

variable "ecr_repository_url" {
  description = "Repository URL of the CreatePendingReservationFn ECR repository (storage/ecr/create-pending-reservation) - the repo itself is owned there, not created in this module"
  type        = string
  sensitive   = true
}

variable "location_table_name" {
  description = "Name of the location DynamoDB table, passed as an environment variable for the handler's SDK calls"
  type        = string
  sensitive   = false
}

variable "published_layout_snapshot_table_name" {
  description = "Name of the published layout snapshot DynamoDB table, passed as an environment variable for the handler's SDK calls"
  type        = string
  sensitive   = false
}

variable "slot_occupancy_table_name" {
  description = "Name of the slot occupancy DynamoDB table, passed as an environment variable for the handler's SDK calls"
  type        = string
  sensitive   = false
}

variable "reservation_table_name" {
  description = "Name of the reservation DynamoDB table, passed as an environment variable for the handler's SDK calls"
  type        = string
  sensitive   = false
}

variable "payment_delinquency_table_name" {
  description = "Name of the payment delinquency DynamoDB table, passed as an environment variable for the handler's SDK calls"
  type        = string
  sensitive   = false
}

variable "stripe_secret_arn" {
  description = "ARN of the platform Stripe API key secret (security/secrets/platform) - the handler reads the key at cold start and calls Stripe on the tenant's connected account"
  type        = string
  sensitive   = false
}

variable "region" {
  description = "AWS region this Lambda's log group, ECR repository, and image push target live in"
  type        = string
  sensitive   = false
}

variable "tenant_table_name" {
  description = "Name of the tenant DynamoDB table - read by the shared tenant-context check (tenant status, plan features, Stripe account, sender)"
  type        = string
  sensitive   = false
}

variable "location_id_index_name" {
  description = "Name of the location table's locationId GSI - resolves a {locationId} from the URL to its tenant"
  type        = string
  sensitive   = false
}

variable "user_table_name" {
  description = "Name of the user DynamoDB table - staff users' assigned location"
  type        = string
  sensitive   = false
}

variable "reservation_link_key_secret_arn" {
  description = "ARN of the Secrets Manager secret holding the HMAC key behind guests' manage links (security/secrets/reservations)"
  type        = string
  sensitive   = false
}

variable "stripe_api_version" {
  description = "Pinned Stripe-Version header for the card-guarantee calls"
  type        = string
  sensitive   = false
}

variable "request_guard_table_name" {
  description = "Name of the request guard DynamoDB table - attempt counters per IP address, phone number and e-mail for online bookings"
  type        = string
  sensitive   = false
}

variable "cloudfront_edge_secret" {
  description = "Shared secret from the admin app's CloudFront (x-booqy-edge); lets shared/http.py trust the viewer IP header"
  type        = string
  sensitive   = true
}

variable "bot_check_enforced" {
  description = "Require guest form posts to come through a restaurant site's /api/* (x-booqy-waf); see root var.bot_check_enforced"
  type        = bool
  sensitive   = false
}

variable "site_waf_secret" {
  description = "Shared secret the sites' CloudFront sends as x-booqy-waf (root random_password.site_waf_edge)"
  type        = string
  sensitive   = true
}

variable "short_link_base" {
  description = "Base of the short SMS card link (https://restaurang.<domain>/api/k), served by get-reservation's GET /k/{code}; \"\" keeps the long URL"
  type        = string
  sensitive   = false
}

variable "phone_card_page" {
  description = "Where a phone guest adds the card: \"site\" (the booking's manage page, only for tenants with cardStepOnManagePage, else Stripe) or \"stripe\""
  type        = string
  sensitive   = false

  validation {
    condition     = contains(["site", "stripe"], var.phone_card_page)
    error_message = "phone_card_page must be site or stripe."
  }
}

variable "notification_function_arn" {
  description = "Alias ARN of notification:live, invoked RequestResponse to text a staff phone booking's card link (CONTRACTS.md 9.4)"
  type        = string
  sensitive   = false
}
