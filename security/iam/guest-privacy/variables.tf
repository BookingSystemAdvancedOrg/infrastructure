variable "environment" {
  description = "The environment to deploy to (dev or prod)"
  type        = string
  sensitive   = false
}

variable "region" {
  type = string
}

variable "tenant_table_arn" {
  type = string
}

variable "consent_table_arn" {
  type = string
}

variable "marketing_table_arn" {
  type = string
}

variable "location_table_arn" {
  type = string
}

variable "guest_table_arns" {
  description = "Reservation, order and catering-requests table ARNs (export and erasure)"
  type        = list(string)
}
