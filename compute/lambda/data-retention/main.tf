# Deletes or anonymises guest data whose retention period is over, for every
# restaurant (application functions/data-retention, rules in
# shared/retention.py, inventory in docs/privacy.md). Invoked ONLY by the
# schedule below and by itself (continuation) - no API route.
#
# Starts in dry run (var.dry_run, root var.data_retention_dry_run = true):
# it only logs counts per data type, so the owner can check them in dev
# before switching it to delete.

locals {
  function_name = var.environment == "prod" ? "data-retention" : "${var.environment}-data-retention"
}

resource "aws_cloudwatch_log_group" "this" {
  name              = "/aws/lambda/${local.function_name}"
  retention_in_days = 30

  tags = {
    Environment = var.environment
  }
}

resource "aws_lambda_function" "this" {
  publish = true

  function_name = local.function_name
  role          = var.role_arn
  package_type  = "Image"
  image_uri     = "${var.ecr_repository_url}:latest"
  # The application pipeline owns the code (see compute/lambda/dlq-replay).
  lifecycle {
    ignore_changes = [image_uri]
  }
  architectures = ["arm64"]

  timeout     = 900
  memory_size = 512

  environment {
    variables = merge({
      ENVIRONMENT                         = var.environment
      DRY_RUN                             = var.dry_run ? "true" : "false"
      TENANT_TABLE_NAME                   = var.tenant_table_name
      TENANT_LIST_INDEX_NAME              = "GSI1"
      LOCATION_TABLE_NAME                 = var.location_table_name
      RESERVATION_TABLE_NAME              = var.reservation_table_name
      ORDER_TABLE_NAME                    = var.order_table_name
      CATERING_REQUESTS_TABLE_NAME        = var.catering_requests_table_name
      CATERING_REQUEST_HISTORY_TABLE_NAME = var.catering_request_history_table_name
      CONSENT_TABLE_NAME                  = var.consent_table_name
      CONSENT_TENANT_INDEX_NAME           = var.consent_tenant_index_name
      MARKETING_TABLE_NAME                = var.marketing_table_name
      ALERT_TOPIC_ARN                     = var.alert_topic_arn
    }, var.retention_env)
  }

  tags = {
    Environment = var.environment
  }

  depends_on = [aws_cloudwatch_log_group.this]
}

# No retries: a failed run emails the operators itself, and every step is
# idempotent, so the next scheduled run finishes the job.
resource "aws_lambda_function_event_invoke_config" "live" {
  function_name                = aws_lambda_function.this.function_name
  qualifier                    = aws_lambda_alias.live.name
  maximum_retry_attempts       = 0
  maximum_event_age_in_seconds = 3600
}

resource "aws_scheduler_schedule" "sweep" {
  name                = local.function_name
  group_name          = "default"
  schedule_expression = var.schedule_expression

  flexible_time_window {
    mode = "OFF"
  }

  target {
    arn      = aws_lambda_alias.live.arn
    role_arn = var.scheduler_invoke_role_arn
    input    = jsonencode({})

    retry_policy {
      maximum_retry_attempts       = 2
      maximum_event_age_in_seconds = 3600
    }
  }
}
