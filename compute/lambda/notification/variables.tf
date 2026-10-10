variable "environment" {
  description = "The environment to deploy to (dev or prod)"
  type        = string
  sensitive   = false
}

variable "role_arn" {
  description = "ARN of the NotificationFn execution role (security/iam/notification)"
  type        = string
  sensitive   = true
}

variable "ecr_repository_url" {
  description = "Repository URL of the NotificationFn ECR repository (storage/ecr/notification) — the repo itself is owned there, not created in this module"
  type        = string
  sensitive   = true
}

variable "no_reply_email_address" {
  description = "No-reply email address used as the SES 'from' address, passed as an environment variable for the handler's SDK calls"
  type        = string
  sensitive   = false
}

variable "admin_dashboard_url" {
  description = "Base URL of the admin front-end (private CloudFront distribution), passed as an environment variable so the handler can build a link-only catering-request notification email - e.g. https://<distribution_domain_name>"
  type        = string
  sensitive   = false
}

variable "region" {
  description = "AWS region this Lambda's log group, ECR repository, and image push target live in"
  type        = string
  sensitive   = false
}

variable "customer_site_url" {
  description = "Base URL of the customer front-end (public CloudFront distribution), e.g. https://<distribution_domain_name> - base of the magic links in catering customer emails"
  type        = string
  sensitive   = false
}

variable "catering_link_signing_key_secret_arn" {
  description = "ARN of the catering magic-link HMAC key secret - the handler rebuilds each customer's link with it"
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
  description = "ARN of the Secrets Manager secret holding the HMAC key behind guests' manage links (security/secrets/reservations)"
  type        = string
  sensitive   = false
}

variable "reservation_table_name" {
  description = "Name of the reservation table - the function tells its stream records apart from the order/catering streams by it"
  type        = string
  sensitive   = false
}
