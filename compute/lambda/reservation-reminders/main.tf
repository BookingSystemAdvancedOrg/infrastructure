# Every 15 minutes: marks bookings that are due a reminder (application
# functions/reservation-reminders). The message itself is sent by
# NotificationFn off the Reservation stream.

locals {
  function_name = var.environment == "prod" ? "reservation-reminders" : "${var.environment}-reservation-reminders"
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
  architectures = ["arm64"]

  timeout     = 120
  memory_size = 256

  environment {
    variables = {
      ENVIRONMENT               = var.environment
      TENANT_TABLE_NAME         = var.tenant_table_name
      LOCATION_TABLE_NAME       = var.location_table_name
      LOCATION_ID_INDEX_NAME    = var.location_id_index_name
      RESERVATION_TABLE_NAME    = var.reservation_table_name
      SLOT_OCCUPANCY_TABLE_NAME = var.slot_occupancy_table_name
    }
  }

  tags = {
    Environment = var.environment
  }

  depends_on = [aws_cloudwatch_log_group.this]
}

# A failed run is simply the next run's work: every booking is claimed with
# a conditional update, so nothing is retried beyond Lambda's own attempts
# and nothing is parked in a DLQ.
resource "aws_lambda_function_event_invoke_config" "live" {
  function_name                = aws_lambda_function.this.function_name
  qualifier                    = aws_lambda_alias.live.name
  maximum_retry_attempts       = 0
  maximum_event_age_in_seconds = 900
}

resource "aws_scheduler_schedule" "reminders" {
  name                = local.function_name
  group_name          = "default"
  schedule_expression = "rate(15 minutes)"

  flexible_time_window {
    mode = "OFF"
  }

  target {
    arn      = aws_lambda_alias.live.arn
    role_arn = var.scheduler_invoke_role_arn
    input    = jsonencode({ source = "schedule" })

    retry_policy {
      maximum_retry_attempts       = 0
      maximum_event_age_in_seconds = 900
    }
  }
}
