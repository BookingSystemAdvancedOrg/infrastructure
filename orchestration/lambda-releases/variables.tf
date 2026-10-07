variable "environment" {
  description = "The environment to deploy to (dev or prod)"
  type        = string
  sensitive   = false
}

variable "functions" {
  description = "Container-image Lambdas released through CodeDeploy: map of function name to its alias name"
  type = map(object({
    alias_name = string
  }))
  sensitive = false
}

variable "traffic_shift_type" {
  description = "AllAtOnce, TimeBasedCanary (percentage for interval minutes, then 100%) or TimeBasedLinear (percentage more every interval minutes)"
  type        = string
  sensitive   = false

  validation {
    condition     = contains(["AllAtOnce", "TimeBasedCanary", "TimeBasedLinear"], var.traffic_shift_type)
    error_message = "traffic_shift_type must be AllAtOnce, TimeBasedCanary or TimeBasedLinear."
  }
}

variable "traffic_shift_percentage" {
  description = "Canary: share of traffic on green during the window. Linear: share added every interval. Ignored for AllAtOnce"
  type        = number
  default     = 10
  sensitive   = false
}

variable "traffic_shift_interval_minutes" {
  description = "Canary: minutes before the rest of the traffic moves. Linear: minutes between steps. Ignored for AllAtOnce"
  type        = number
  default     = 5
  sensitive   = false
}

variable "rollback_alarms_enabled" {
  description = "Create the per-function error-rate and throttle alarms and roll releases back when they fire. Each alarm is billed monthly even when idle, so this is meant for prod only"
  type        = bool
  sensitive   = false
}

variable "alert_topic_arn" {
  description = "Platform alerts SNS topic (monitoring/alerts) - rollback alarms and release results are emailed through it"
  type        = string
  sensitive   = false
}

variable "error_rate_threshold_percent" {
  description = "Error rate (%) on a function's live alias, within one minute, that rolls a release back"
  type        = number
  default     = 5
  sensitive   = false
}

variable "min_errors" {
  description = "Errors needed in a minute before the error rate counts - stops a single error at very low traffic from rolling a release back"
  type        = number
  default     = 3
  sensitive   = false
}

variable "throttle_threshold" {
  description = "Throttled invocations on a live alias, within one minute, that roll a release back"
  type        = number
  default     = 5
  sensitive   = false
}
