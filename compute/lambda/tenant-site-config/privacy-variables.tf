variable "privacy_env" {
  description = "Extra environment variables from the root privacy-consent.tf (consent log table, retention periods). Empty = the function runs as before."
  type        = map(string)
  sensitive   = false
  default     = {}
}
