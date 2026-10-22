# Writes the figures behind Statistik in the admin app: for every active
# restaurant location and day, the bookings per hour and source, table
# minutes booked and open, orders, dishes, catering and website visits
# (storage/dynamodb/insights). Invoked ONLY by the schedule below and by
# itself (continuation, or a backfill {"from", "to"} started by hand) - no
# API route. Code: the application repo, functions/insights-rollup.
#
# Nightly rather than per event: bookings change after the day (no-shows
# are marked late, fees are charged and refunded, catering moves on), so
# every run recomputes the last ROLLUP_DAYS days instead of keeping running
# counters in step. The day being served is computed live by insights.

locals {
  function_name = var.environment == "prod" ? "insights-rollup" : "${var.environment}-insights-rollup"
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
  # One run at a time: two runs would only overwrite each other's rows.
  reserved_concurrent_executions = var.reserved_concurrency

  environment {
    variables = {
      ENVIRONMENT                          = var.environment
      INSIGHTS_TABLE_NAME                  = var.insights_table_name
      TENANT_TABLE_NAME                    = var.tenant_table_name
      TENANT_LIST_INDEX_NAME               = "GSI1"
      LOCATION_TABLE_NAME                  = var.location_table_name
      RESERVATION_TABLE_NAME               = var.reservation_table_name
      ORDER_TABLE_NAME                     = var.order_table_name
      CATERING_REQUESTS_TABLE_NAME         = var.catering_requests_table_name
      PUBLISHED_LAYOUT_SNAPSHOT_TABLE_NAME = var.published_layout_snapshot_table_name
      MARKETING_TABLE_NAME                 = var.marketing_table_name
      ROLLUP_DAYS                          = "8"
      BACKFILL_DAYS                        = "395"
    }
  }

  tags = {
    Environment = var.environment
  }

  depends_on = [aws_cloudwatch_log_group.this]
}

# No retries: every step is idempotent and the next scheduled run simply
# does the days again.
resource "aws_lambda_function_event_invoke_config" "live" {
  function_name                = aws_lambda_function.this.function_name
  qualifier                    = aws_lambda_alias.live.name
  maximum_retry_attempts       = 0
  maximum_event_age_in_seconds = 3600
}

resource "aws_scheduler_schedule" "nightly" {
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
