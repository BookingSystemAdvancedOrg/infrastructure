variable "environment" {
  description = "dev or prod"
  type        = string
  sensitive   = false
}

variable "api_rate_limit" {
  description = "Requests to /api/* per IP per 5 minutes on the restaurant websites before the IP gets 429 for a while"
  type        = number
  sensitive   = false
  default     = 300

  validation {
    condition     = var.api_rate_limit >= 10
    error_message = "api_rate_limit must be at least 10 (the WAF minimum)."
  }
}
