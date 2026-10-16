variable "environment" {
  description = "The environment to deploy to (dev or prod) - prod gets 7-year COMPLIANCE retention, every other environment 1-day GOVERNANCE"
  type        = string
  sensitive   = false
}
