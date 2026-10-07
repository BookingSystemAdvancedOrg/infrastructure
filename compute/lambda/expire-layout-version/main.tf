locals {
  function_name = var.environment == "prod" ? "expire-layout-version" : "${var.environment}-expire-layout-version"
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

  timeout     = 28
  memory_size = 512

  environment {
    variables = {
      TENANT_TABLE_NAME                    = var.tenant_table_name
      LOCATION_TABLE_NAME                  = var.location_table_name
      LOCATION_ID_INDEX_NAME               = var.location_id_index_name
      ENVIRONMENT                          = var.environment
      PUBLISHED_LAYOUT_SNAPSHOT_TABLE_NAME = var.published_layout_snapshot_table_name
    }
  }

  tags = {
    Environment = var.environment
  }
}

# EventBridge Scheduler invokes this function ASYNCHRONOUSLY, so a failing
# run is handled by Lambda's async retry logic, not by Scheduler: after the
# retries below, Lambda hands the invocation record (original input in
# requestPayload) to the scheduled-invocation DLQ. Configured here, so no
# application code has to set anything per schedule. dlq-replay redelivers
# from that queue on its own schedule.
resource "aws_lambda_function_event_invoke_config" "this" {
  function_name                = aws_lambda_function.this.function_name
  maximum_retry_attempts       = 2
  maximum_event_age_in_seconds = 21600 # 6h - a timer older than that is stale

  destination_config {
    on_failure {
      destination = var.failure_destination_arn
    }
  }
}
