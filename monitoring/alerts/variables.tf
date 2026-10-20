variable "environment" {
  description = "The environment to deploy to (dev or prod)"
  type        = string
  sensitive   = false
}

variable "region" {
  description = "AWS region the alarms live in - scopes the topic policy to this account's alarms"
  type        = string
  sensitive   = false
}

variable "alert_emails" {
  description = "Email addresses subscribed to the platform alerts topic (each must confirm once)"
  type        = list(string)
  sensitive   = false
}

variable "dlq_queue_names" {
  description = "Map of DLQ key to queue name (storage/sqs/dead-letter) - one stuck-message alarm per queue"
  type        = map(string)
  sensitive   = false
}

variable "replay_function_name" {
  description = "Name of the dlq-replay Lambda - alarmed on its Errors metric"
  type        = string
  sensitive   = false
}

variable "replay_interval_minutes" {
  description = "Replay interval in minutes - a DLQ message older than two intervals counts as stuck"
  type        = number
  sensitive   = false
}

variable "sms_monthly_spend_limit_usd" {
  description = "Account-wide monthly SMS spend limit in USD (aws_sns_sms_preferences) - can't exceed the account's SMS quota; alarmed at 80%. null = the account's SMS settings aren't managed here"
  type        = number
  sensitive   = false
  default     = null
}

# --- front-door alarms and uptime check (front-door.tf, uptime.tf) ----------

variable "api_id" {
  description = "ID of the HTTP API (network/api-gateway) - its 5xx rate and p99 latency are alarmed"
  type        = string
  sensitive   = false
}

variable "api_name" {
  description = "Name of the HTTP API, for the alarm texts"
  type        = string
  sensitive   = false
}

variable "api_endpoint" {
  description = "Base invoke URL of the HTTP API - the uptime check calls <api_endpoint>/site-config"
  type        = string
  sensitive   = false
}

variable "cloudfront_distributions" {
  description = "Distributions whose 5xx rate is alarmed: short name => distribution ID (admin, customer, tenant sites when on)"
  type        = map(string)
  sensitive   = false
  default     = {}
}

variable "customer_site_url" {
  description = "URL the uptime check loads as the customer site (a test restaurant's host when one is known, else the public distribution)"
  type        = string
  sensitive   = false
}

variable "admin_app_url" {
  description = "URL of the restaurant admin app - loaded by the uptime check"
  type        = string
  sensitive   = false
}

variable "smoke_test_host" {
  description = "Hostname of a restaurant that always exists in this environment (e.g. test-restaurang-2.dev.booqy.se). GET /site-config?host=<this> must answer 200. Empty = the check expects 404 for an unknown host instead"
  type        = string
  sensitive   = false
  default     = ""
}

variable "uptime_check_enabled" {
  description = "Run the 5-minute uptime check Lambda and its alarms"
  type        = bool
  sensitive   = false
  default     = true
}

variable "api_5xx_threshold_percent" {
  description = "Share of API requests (5 minutes) answered 5xx that alarms"
  type        = number
  sensitive   = false
  default     = 5
}

variable "api_min_errors" {
  description = "5xx responses needed in a 5-minute period before the 5xx rate counts - keeps one failed request at low traffic from alarming"
  type        = number
  sensitive   = false
  default     = 5
}

variable "api_p99_latency_threshold_ms" {
  description = "API p99 latency (ms, 5-minute periods) above which two of three periods alarm - above the container Lambdas' cold starts"
  type        = number
  sensitive   = false
  default     = 5000
}

variable "cloudfront_5xx_threshold_percent" {
  description = "5xx share of a distribution's requests (5 minutes) that alarms when it holds for two periods"
  type        = number
  sensitive   = false
  default     = 5
}

variable "cloudfront_min_requests" {
  description = "Requests a distribution must have seen in a 5-minute period before its 5xx rate counts"
  type        = number
  sensitive   = false
  default     = 20
}
