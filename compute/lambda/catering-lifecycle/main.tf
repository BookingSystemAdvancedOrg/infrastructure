# Status-change and timer handler for the catering workflow. The schedules it
# creates target THIS function: the handler takes its own ARN from
# context.invoked_function_arn (it can't be passed in here - a function's
# environment can't reference its own ARN).
#
# Schedule names are deterministic (<action>-<requestId>), so a retried
# stream record re-creates the same schedule instead of a duplicate, and
# every schedule is created with ActionAfterCompletion = DELETE and
# DeadLetterConfig = SCHEDULER_DLQ_ARN.

locals {
  function_name = var.environment == "prod" ? "catering-lifecycle" : "${var.environment}-catering-lifecycle"
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

  timeout     = 60
  memory_size = 512

  environment {
    variables = {
      TENANT_TABLE_NAME                   = var.tenant_table_name
      LOCATION_ID_INDEX_NAME              = var.location_id_index_name
      ENVIRONMENT                         = var.environment
      CATERING_REQUESTS_TABLE_NAME        = var.catering_requests_table_name
      CATERING_REQUEST_HISTORY_TABLE_NAME = var.catering_request_history_table_name
      LOCATION_TABLE_NAME                 = var.location_table_name
      STRIPE_SECRET_ARN                   = var.stripe_secret_arn
      STRIPE_API_VERSION                  = var.stripe_api_version
      SCHEDULE_GROUP_NAME                 = var.schedule_group_name
      SCHEDULER_INVOKE_ROLE_ARN           = var.scheduler_invoke_role_arn
      SCHEDULER_DLQ_ARN                   = var.scheduler_dlq_arn
    }
  }

  tags = {
    Environment = var.environment
  }

  depends_on = [aws_cloudwatch_log_group.this]
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
