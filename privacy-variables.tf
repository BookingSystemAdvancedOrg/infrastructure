# Guest data retention and the marketing consent log (privacy-consent.tf).
# The rules per data type: application shared/retention.py and
# docs/privacy.md. Items marked LEGAL REVIEW are defaults the restaurants'
# lawyer should confirm.

variable "data_retention" {
  description = <<-EOT
    How long guest data is kept (all whole numbers):
      booking_days          plain bookings, deleted this many days after the visit (395 = about 13 months, as before)
      guest_months          names and contact details on orders and catering requests are removed after this
      cancelled_months      declined/rejected/expired/cancelled quotes and never-paid orders are deleted after this
      accounting_years      receipts and accounting records (bokföringslagen: 7 years after the year's end)
      suppression_months    LEGAL REVIEW: a withdrawn consent is kept as a bare "do not contact" record this long
      consent_history_days  LEGAL REVIEW: the full consent history is kept this long after a withdrawal
  EOT
  type = object({
    booking_days         = optional(number, 395)
    guest_months         = optional(number, 24)
    cancelled_months     = optional(number, 12)
    accounting_years     = optional(number, 7)
    suppression_months   = optional(number, 36)
    consent_history_days = optional(number, 30)
  })
  sensitive = false
  default   = {}

  validation {
    condition = alltrue([
      var.data_retention.booking_days >= 30 && var.data_retention.booking_days <= 1100,
      var.data_retention.guest_months >= 1 && var.data_retention.guest_months <= 120,
      var.data_retention.cancelled_months >= 1 && var.data_retention.cancelled_months <= 120,
      var.data_retention.accounting_years >= 7 && var.data_retention.accounting_years <= 11,
      var.data_retention.suppression_months >= 1 && var.data_retention.suppression_months <= 120,
      var.data_retention.consent_history_days >= 1 && var.data_retention.consent_history_days <= 3650,
    ])
    error_message = "data_retention: booking_days 30-1100, months 1-120, accounting_years 7-11 (never below the Bookkeeping Act), consent_history_days 1-3650."
  }
}

variable "data_retention_dry_run" {
  type        = bool
  description = "true = the data-retention job only logs counts per data type and changes nothing. Check the counts in dev, then set false."
  sensitive   = false
  default     = true
}

variable "data_retention_schedule" {
  type        = string
  description = "EventBridge Scheduler expression for the data-retention sweep (UTC). A missed run only means a later deletion."
  sensitive   = false
  default     = "cron(30 2 * * ? *)"
}
