variable "environment" {
  description = "The environment to deploy to (dev or prod)"
  type        = string
  sensitive   = false
}

variable "plans" {
  description = "Plan catalog written to the table as PLAN#<id> rows - max_locations and feature flags per package"
  type = map(object({
    name          = string
    max_locations = number
    features      = map(bool)
    price_sek     = number
  }))
  sensitive = false
}

variable "plan_price_ids" {
  description = "Stripe price id per plan id (payments/billing) - stored on the PLAN# rows as stripePriceId"
  type        = map(string)
  sensitive   = false
}
