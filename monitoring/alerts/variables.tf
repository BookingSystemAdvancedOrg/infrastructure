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
