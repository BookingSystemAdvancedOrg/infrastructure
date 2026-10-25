variable "guest_privacy_invoke_arn" {
  description = "Invoke ARN (live alias) of the guest-privacy Lambda (owner privacy API)"
  type        = string
  sensitive   = false
}

variable "guest_privacy_function_name" {
  description = "Name of the guest-privacy Lambda"
  type        = string
  sensitive   = false
}
