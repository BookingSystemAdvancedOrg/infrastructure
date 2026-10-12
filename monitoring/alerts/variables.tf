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
