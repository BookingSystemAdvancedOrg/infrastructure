variable "environment" {
  description = "The environment to deploy to (dev or prod)"
  type        = string
  sensitive   = false
}

variable "role_arn" {
  description = "ARN of the DlqReplayFn execution role (security/iam/dlq-replay)"
  type        = string
  sensitive   = true
}

variable "ecr_repository_url" {
  description = "Repository URL of the DlqReplayFn ECR repository (storage/ecr/dlq-replay) — the repo itself is owned there, not created in this module"
  type        = string
  sensitive   = true
}

variable "catering_lifecycle_function_arn" {
  description = "ARN of the catering-lifecycle Lambda - target for catering-lifecycle-stream-dlq and reconcile"
  type        = string
  sensitive   = false
}

variable "notification_function_arn" {
  description = "ARN of the NotificationFn Lambda - target for notification-stream-dlq"
  type        = string
  sensitive   = false
}

variable "alert_topic_arn" {
  description = "ARN of the alerts SNS topic"
  type        = string
  sensitive   = false
}

variable "scheduler_invoke_role_arn" {
  description = "ARN of the role EventBridge Scheduler assumes to invoke this function"
  type        = string
  sensitive   = true
}

variable "region" {
  description = "AWS region this Lambda's log group, ECR repository, and image push target live in"
  type        = string
  sensitive   = false
}

variable "queue_urls" {
  description = "Map of DLQ key (lifecycle_stream, notification_stream, scheduled_invocation) to queue URL (storage/sqs/dead-letter)"
  type        = map(string)
  sensitive   = false
}

variable "replayable_function_arns" {
  description = "ARNs of the scheduler-invoked functions whose failed invocations may be redelivered from the scheduled-invocation DLQ - an allow-list checked by the handler"
  type        = list(string)
  sensitive   = false
}

variable "replay_interval_minutes" {
  description = "How often the replay runs, in minutes - set per environment via dlq_replay_interval_minutes"
  type        = number
  sensitive   = false
}
