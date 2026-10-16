variable "environment" {
  description = "The environment to deploy to (dev or prod)"
  type        = string
  sensitive   = false
}

variable "stripe_secret_key" {
  description = "Platform Stripe secret key used only to seed the secret on first apply"
  type        = string
  sensitive   = true
}
