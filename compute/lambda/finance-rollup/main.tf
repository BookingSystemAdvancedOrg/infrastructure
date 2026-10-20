# Writes the figures behind the Finance page in Booqy Console: pulls the
# account's cost per service from Cost Explorer, counts each customer's
# usage (API requests from the Lambda logs, bookings and orders from their
# tables, emails and SMS from the counters the senders bump), allocates the
# cost over the customers active that day and writes one row per customer
# per day plus the platform totals (storage/dynamodb/finance). Invoked ONLY
# by the schedule below, by Booqy Console's Rebuild (platform-tenants, a
# date range) and by itself (continuation) - no API route. Code: the
# application repo, functions/finance-rollup.
#
# Nightly rather than per event: Cost Explorer has a day's cost ready a few
# hours after midnight UTC and restates it for a few days, so every run
# recomputes the last days instead of trusting a single pass.

locals {
  function_name = var.environment == "prod" ? "finance-rollup" : "${var.environment}-finance-rollup"
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
      ENVIRONMENT             = var.environment
      FINANCE_TABLE_NAME      = var.finance_table_name
      TENANT_TABLE_NAME       = var.tenant_table_name
      TENANT_LIST_INDEX_NAME  = "GSI1"
      LOCATION_TABLE_NAME     = var.location_table_name
      RESERVATION_TABLE_NAME  = var.reservation_table_name
      ORDER_TABLE_NAME        = var.order_table_name
      LAMBDA_LOG_GROUP_PREFIX = "/aws/lambda/${var.environment == "prod" ? "" : "${var.environment}-"}"
      LAMBDA_LOG_GROUPS       = jsonencode(var.log_group_names)
      COST_DAYS               = "7"
      USAGE_DAYS              = "3"
      USD_TO_SEK              = tostring(var.usd_to_sek)
      COST_ALLOCATION         = jsonencode(var.cost_allocation)
      ALERT_TOPIC_ARN         = var.alert_topic_arn
    }
  }

  tags = {
    Environment = var.environment
  }

  depends_on = [aws_cloudwatch_log_group.this]
}

# No retries: every step is idempotent and the next scheduled run (or a
# Rebuild from Booqy Console) simply does the day again; warnings go to the
# alert topic.
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
