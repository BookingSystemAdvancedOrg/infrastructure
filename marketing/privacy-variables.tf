variable "consent_table_name" {
  description = "Consent log table (root privacy-consent.tf): marketing-send checks it before every email, marketing-public and marketing-sync append withdrawals. Empty = not configured."
  type        = string
  sensitive   = false
  default     = ""
}
