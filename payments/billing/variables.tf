variable "environment" {
  description = "The environment to deploy to (dev or prod)"
  type        = string
  sensitive   = false
}

variable "plans" {
  description = "The plan catalog (root var.plans): one Stripe product and monthly price per entry"
  type = map(object({
    name          = string
    max_locations = number
    features      = map(bool)
    price_sek     = number
  }))
  sensitive = false
}
