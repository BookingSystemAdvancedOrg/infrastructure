# Deletes offboarded restaurants' data once their retention period is over
# (purgeAt on the tenant PROFILE, written by the offboarding workflow).
# Invoked ONLY by the schedule below and by itself (continuation when a run
# gets close to its timeout) - no API route. Code: the application repo,
# functions/tenant-purge.
#
# A daily sweep instead of one timer per restaurant: no execution or
# schedule per tenant to keep in sync, so changing the retention, deleting
# early (Booqy Console sets purgeAt to now) or fixing the code applies to
# every restaurant on the next run.

locals {
  function_name = var.environment == "prod" ? "tenant-purge" : "${var.environment}-tenant-purge"
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
  # One run at a time: two sweeps would only repeat each other's deletes.
  reserved_concurrent_executions = var.reserved_concurrency

  environment {
    variables = merge({
      ENVIRONMENT                         = var.environment
      TENANT_TABLE_NAME                   = var.tenant_table_name
      TENANT_LIST_INDEX_NAME              = "GSI1"
      LOCATION_TABLE_NAME                 = var.location_table_name
      USER_TABLE_NAME                     = var.user_table_name
      USER_TENANT_INDEX_NAME              = var.user_tenant_index_name
      COGNITO_USER_POOL_ID                = var.tenant_user_pool_id
      LOCATION_TABLE_NAMES                = jsonencode(var.location_table_names)
      CATERING_REQUESTS_TABLE_NAME        = var.catering_requests_table_name
      CATERING_REQUEST_HISTORY_TABLE_NAME = var.catering_request_history_table_name
      MARKETING_TABLE_NAME                = var.marketing_table_name
      MENU_IMAGES_BUCKET_NAME             = var.menu_image_bucket_name
      RETENTION_DAYS                      = tostring(var.retention_days)
      BACKFILL_GRACE_DAYS                 = "7"
      ALERT_TOPIC_ARN                     = var.alert_topic_arn
      PROTECTED_ZONE_IDS                  = jsonencode(var.protected_zone_ids)
    }, var.privacy_env) # consent log (root privacy-consent.tf)
  }

  tags = {
    Environment = var.environment
  }

  depends_on = [aws_cloudwatch_log_group.this]
}

# No retries: a failed run emails the operators itself, and every step is
# idempotent, so the next scheduled run simply finishes the job.
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
