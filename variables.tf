
variable "env" {
  type        = string
  description = "The environment to deploy to (dev or prod)"
  sensitive   = false
}
variable "aws_region" {
  type        = string
  description = "The AWS region to deploy to"
  sensitive   = false
}
variable "no_reply_email_address" {
  type        = string
  description = "The email address to use for sending no-reply emails"
  sensitive   = false
}
variable "stripe_api_version" {
  type        = string
  description = "Pinned Stripe API version the Lambdas are coded against, e.g. 2026-07-29.dahlia"
  sensitive   = false
}
variable "stripe_secret_key" {
  type        = string
  description = "Stripe secret API key (sk_...) - dev or prod value depending on which environment is deploying"
  sensitive   = true
}
variable "stripe_webhook_secret" {
  type        = string
  description = "Signing secret (whsec_...) for the stripe-webhook endpoint - dev or prod value depending on which environment is deploying"
  sensitive   = true
}
variable "github_org" {
  type        = string
  description = "Shared GitHub organization all three OIDC-trusted repos live under - combined with each *_repo variable below to build the \"org/repo-name\" each role's trust policy matches against"
  sensitive   = false
}
variable "customer_frontend_repo" {
  type        = string
  description = "Customer front-end repo name (no org prefix) - trusted by security/iam/oidc/customer-front-end-role's trust policy"
  sensitive   = false
}
variable "admin_frontend_repo" {
  type        = string
  description = "Admin front-end repo name (no org prefix) - trusted by security/iam/oidc/admin-front-end-role's trust policy"
  sensitive   = false
}
variable "backend_repo" {
  type        = string
  description = "Backend repo name (no org prefix) - trusted by security/iam/oidc/back-end-role's trust policy"
  sensitive   = false
}
