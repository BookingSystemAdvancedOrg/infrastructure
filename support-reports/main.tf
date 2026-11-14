# Error reports from Booqy Admin ("Rapportera till Booqy"). Application:
# functions/support-reports. A restaurant user (owner or staff) posts a
# report about an error that is Booqy's fault; the Lambda stores it in the
# support-reports table (180 days, TTL), publishes it to the platform alerts
# topic (the operators' email) and serves Booqy Console's Reports list and
# "mark handled". Per user 10 reports an hour (request-guard counters); the
# same report within 10 minutes is stored once. Never secrets, tokens or
# form contents: the body takes only code, status, path, requestId and
# appVersion, each validated.

data "aws_caller_identity" "current" {}

locals {
  prefix        = var.environment == "prod" ? "" : "${var.environment}-"
  account       = data.aws_caller_identity.current.account_id
  function_name = "${local.prefix}support-reports"
}

resource "aws_iam_role" "fn" {
  name = "${local.function_name}-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect    = "Allow"
      Principal = { Service = "lambda.amazonaws.com" }
      Action    = "sts:AssumeRole"
    }]
  })

  tags = {
    Environment = var.environment
  }
}

# Reports table: put a report and its dedupe marker, read the marker, list
# (Query on REPORTS), mark handled (UpdateItem), give back a marker when the
# rate limit refuses (DeleteItem). No Scan. Request-guard: the per-user
# counter. Alerts topic: one message per new report.
resource "aws_iam_role_policy" "fn" {
  name = "support-reports-access"
  role = aws_iam_role.fn.id
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid      = "SupportReports"
        Effect   = "Allow"
        Action   = ["dynamodb:PutItem", "dynamodb:GetItem", "dynamodb:Query", "dynamodb:UpdateItem", "dynamodb:DeleteItem"]
        Resource = var.table_arn
      },
      {
        Sid      = "RequestGuardCounters"
        Effect   = "Allow"
        Action   = ["dynamodb:UpdateItem"]
        Resource = var.request_guard_table_arn
      },
      {
        Sid      = "NotifyOperators"
        Effect   = "Allow"
        Action   = "sns:Publish"
        Resource = var.alert_topic_arn
      },
    ]
  })
}

resource "aws_iam_role_policy" "logs" {
  name = "cloudwatch-logs"
  role = aws_iam_role.fn.id
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Sid      = "WriteLogs"
      Effect   = "Allow"
      Action   = ["logs:CreateLogStream", "logs:PutLogEvents"]
      Resource = "arn:aws:logs:${var.region}:${local.account}:log-group:/aws/lambda/${local.function_name}:*"
    }]
  })
}

resource "aws_cloudwatch_log_group" "fn" {
  name              = "/aws/lambda/${local.function_name}"
  retention_in_days = 30

  tags = {
    Environment = var.environment
  }
}

resource "aws_lambda_function" "fn" {
  function_name = local.function_name
  role          = aws_iam_role.fn.arn
  package_type  = "Image"
  image_uri     = "${var.ecr_repository_url}:latest"
  publish       = true
  architectures = ["arm64"]
  timeout       = 10
  memory_size   = 256

  lifecycle {
    ignore_changes = [image_uri]
  }

  environment {
    variables = {
      ENVIRONMENT                = var.environment
      TENANT_TABLE_NAME          = var.tenant_table_name
      LOCATION_TABLE_NAME        = var.location_table_name
      LOCATION_ID_INDEX_NAME     = var.location_id_index_name
      SUPPORT_REPORTS_TABLE_NAME = var.table_name
      REQUEST_GUARD_TABLE_NAME   = var.request_guard_table_name
      ALERT_TOPIC_ARN            = var.alert_topic_arn
      CONSOLE_APP_URL            = var.console_app_url
    }
  }

  depends_on = [aws_cloudwatch_log_group.fn, aws_iam_role_policy.logs]

  tags = {
    Environment = var.environment
  }
}

resource "aws_lambda_alias" "live" {
  name             = "live"
  function_name    = aws_lambda_function.fn.function_name
  function_version = aws_lambda_function.fn.version

  lifecycle {
    ignore_changes = [function_version, routing_config]
  }
}

# --- alarms --------------------------------------------------------------------------------

resource "aws_cloudwatch_metric_alarm" "errors" {
  alarm_name          = "${local.function_name}-errors"
  alarm_description   = "support-reports Lambda errors"
  namespace           = "AWS/Lambda"
  metric_name         = "Errors"
  dimensions          = { FunctionName = aws_lambda_function.fn.function_name }
  statistic           = "Sum"
  period              = 300
  evaluation_periods  = 1
  threshold           = 1
  comparison_operator = "GreaterThanOrEqualToThreshold"
  treat_missing_data  = "notBreaching"
  alarm_actions       = [var.alert_topic_arn]

  tags = {
    Environment = var.environment
  }
}
