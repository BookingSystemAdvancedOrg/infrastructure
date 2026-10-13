variable "environment" {
  description = "The environment to deploy to - never prod (the module call has count = 0 there)"
  type        = string
  sensitive   = false

  validation {
    condition     = var.environment != "prod"
    error_message = "The mail outbox is for non-prod environments only."
  }
}
