variable "environment" {
  description = "The environment to deploy to (dev or prod)"
  type        = string
  sensitive   = false
}

variable "role_arn" {
  description = "ARN of the PaymentIntentFn execution role (security/iam/payment-intent)"
  type        = string
  sensitive   = true
}

variable "ecr_repository_url" {
  description = "Repository URL of the PaymentIntentFn ECR repository (storage/ecr/payment-intent) - the repo itself is owned there, not created in this module"
  type        = string
  sensitive   = true
}

variable "order_table_name" {
  description = "Name of the order DynamoDB table, passed as an environment variable for the handler's SDK calls"
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

variable "location_table_name" {
  description = "Name of the location DynamoDB table, passed as an environment variable"
  type        = string
  sensitive   = false
}

variable "location_id_index_name" {
  description = "Name of the location table's locationId GSI - resolves a {locationId} from the URL to its tenant"
  type        = string
  sensitive   = false
}

variable "reservation_link_key_secret_arn" {
  description = "ARN of the guest-link HMAC key secret (security/secrets/reservations) - signs order status links and table QR codes"
  type        = string
  sensitive   = false
}

variable "stripe_api_version" {
  description = "Pinned Stripe-Version header"
  type        = string
  sensitive   = false
}

variable "menu_table_name" {
  description = "Name of the menu table (prices)"
  type        = string
  sensitive   = false
}

variable "customer_site_url" {
  description = "Base URL of the guest site in dev (Stripe return pages with ?restaurang=); unused once a tenant has its own domain"
  type        = string
  sensitive   = false
}

variable "turnstile_required" {
  description = "Whether online orders must carry a Cloudflare Turnstile token - true once the platform's widget is configured"
  type        = bool
  sensitive   = false
  default     = false
}

variable "turnstile_secret_arn" {
  description = "ARN of the platform's Turnstile secret"
  type        = string
  sensitive   = false
}

variable "request_guard_table_name" {
  description = "Name of the attempt-counter table"
  type        = string
  sensitive   = false
}

variable "cloudfront_edge_secret" {
  description = "Shared secret from the admin app's CloudFront (x-booqy-edge); lets shared/http.py trust the viewer IP header"
  type        = string
  sensitive   = true
}
