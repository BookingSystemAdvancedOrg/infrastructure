# Scheduled dead-letter replay for every asynchronous path in the platform
# (see security/iam/dlq-replay for what it may touch). Invoked ONLY by the
# schedule below - no API route, no event source mapping. A queue trigger
# would retry failures immediately, before anyone has fixed whatever made
# them fail; a schedule retries on a deliberate cadence and escalates after
# MAX_REPLAY_ATTEMPTS.
#
# Reference implementation: src/handler.py. Like every Lambda here, the
# deployed image is built and pushed by the backend repo's pipeline.

locals {
  function_name = var.environment == "prod" ? "dlq-replay" : "${var.environment}-dlq-replay"
}

# Declared explicitly, not left to be auto-created on first invoke, so log
# retention is actually controlled instead of defaulting to "never expire".
resource "aws_cloudwatch_log_group" "this" {
  name              = "/aws/lambda/${local.function_name}"
  retention_in_days = 30

  tags = {
    Environment = var.environment
  }
}

resource "aws_lambda_function" "this" {
  function_name = local.function_name
  role          = var.role_arn
  package_type  = "Image"
  image_uri     = "${var.ecr_repository_url}:latest"
  architectures = ["arm64"]

  timeout     = 300
  memory_size = 256

  environment {
    variables = {
      ENVIRONMENT                     = var.environment
      LIFECYCLE_STREAM_DLQ_URL        = var.queue_urls["lifecycle_stream"]
      NOTIFICATION_STREAM_DLQ_URL     = var.queue_urls["notification_stream"]
      SCHEDULED_INVOCATION_DLQ_URL    = var.queue_urls["scheduled_invocation"]
      CATERING_LIFECYCLE_FUNCTION_ARN = var.catering_lifecycle_function_arn
      NOTIFICATION_FUNCTION_ARN       = var.notification_function_arn
      REPLAYABLE_FUNCTION_ARNS        = jsonencode(var.replayable_function_arns) # allow-list for scheduled-invocation redelivery
      ALERT_TOPIC_ARN                 = var.alert_topic_arn
      MAX_REPLAY_ATTEMPTS             = "3"
      STREAM_RETENTION_HOURS          = "23" # stream records live 24h; 1h safety margin
    }
  }

  tags = {
    Environment = var.environment
  }

  depends_on = [aws_cloudwatch_log_group.this]
}

# Recurring schedule that runs the replay. Unlike the per-request timers
# (created at runtime by catering-lifecycle, stripe-webhook, manage-menu,
# activate-layout-version), this one is permanent, so it lives here in
# Terraform, in the default schedule group.
#
# The interval is set per environment (dlq_replay_interval_minutes in
# <env>.tfvars): short in dev to see replays work, longer in prod. Keep it
# under 24h so stream-DLQ pointers can still be replayed from the stream
# (older ones are reconciled or escalated instead), and above this
# function's 300s timeout so two runs never overlap (overlap would still be
# safe - a received message is invisible to others for 330s - just wasteful).
#
# This schedule's own invocations are NOT routed to the scheduled-invocation
# DLQ (this function has no async destination): a failed replay run is
# simply retried by the next one, and the Errors alarm (monitoring/alerts)
# reports it.
resource "aws_scheduler_schedule" "replay" {
  name                = local.function_name
  group_name          = "default"
  schedule_expression = "rate(${var.replay_interval_minutes} ${var.replay_interval_minutes == 1 ? "minute" : "minutes"})"

  flexible_time_window {
    mode = "OFF"
  }

  target {
    arn      = aws_lambda_function.this.arn
    role_arn = var.scheduler_invoke_role_arn
    input    = jsonencode({ queue = "all", max = 50 })

    retry_policy {
      maximum_retry_attempts       = 2
      maximum_event_age_in_seconds = 300
    }
  }
}
