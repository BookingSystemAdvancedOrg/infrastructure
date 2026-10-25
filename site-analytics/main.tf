# Cookieless statistics for the public site (booqy-website): visits,
# sources, pages, countries, devices and demo bookings, shown on Booqy
# Console's Website page. Nothing is stored on the visitor's device, so no
# consent banner is needed; see src/handler.py for what is counted and how.
#
#   site/assets/stats.js --GET /api/collect--> landing CloudFront (OAC, viewer
#   geo headers) --> this function's URL (AWS_IAM) --> raw hits (30 days)
#   EventBridge Scheduler (every 15 min) --> same function {"task": "rollup"}
#   --> one aggregate per day (25 months) <-- platform-tenants (Website page)
#
# A zip from this repo like demo-request: no dependencies, nothing for the
# backend repo to own, no API Gateway in front (same origin as the site).
# Tests in tests/ (python3 -m unittest discover -s site-analytics/tests).

terraform {
  required_providers {
    archive = {
      source = "hashicorp/archive"
    }
  }
}

data "aws_caller_identity" "current" {}

locals {
  prefix        = var.environment == "prod" ? "" : "${var.environment}-"
  function_name = "${local.prefix}site-analytics"
}

# Raw hits (PK RAW#<Stockholm day>, SK <epoch ms>#<random>, 30-day TTL), the
# daily aggregates (PK AGG, SK DAY#<day>, 25-month TTL) and the last rollup
# (PK JOB, SK latest). Visitor hashes only: no IP, no user agent.
resource "aws_dynamodb_table" "analytics" {
  name         = "${local.prefix}site-analytics"
  billing_mode = "PAY_PER_REQUEST"
  hash_key     = "PK"
  range_key    = "SK"

  attribute {
    name = "PK"
    type = "S"
  }

  attribute {
    name = "SK"
    type = "S"
  }

  ttl {
    attribute_name = "expiresAt"
    enabled        = true
  }

  point_in_time_recovery {
    enabled = true
  }

  server_side_encryption {
    enabled = true
  }

  tags = {
    Environment = var.environment
  }
}

# The day's salt (PK SALT#<day>). Its own table WITHOUT point-in-time
# recovery on purpose: a backup of an old salt would let old hashes be
# matched against an IP address again. Deleted by the rollup once the day is
# over, TTL as a backstop.
resource "aws_dynamodb_table" "state" {
  name         = "${local.prefix}site-analytics-state"
  billing_mode = "PAY_PER_REQUEST"
  hash_key     = "PK"

  attribute {
    name = "PK"
    type = "S"
  }

  ttl {
    attribute_name = "expiresAt"
    enabled        = true
  }

  server_side_encryption {
    enabled = true
  }

  tags = {
    Environment = var.environment
  }
}

# --- function ------------------------------------------------------------------

resource "aws_iam_role" "this" {
  name = "${local.function_name}-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect    = "Allow"
        Principal = { Service = "lambda.amazonaws.com" }
        Action    = "sts:AssumeRole"
      }
    ]
  })

  tags = {
    Environment = var.environment
  }
}

# Least privilege: its own log group, write and read the two tables. No
# logs:CreateLogGroup (the group is provisioned below), nothing else.
resource "aws_iam_role_policy" "this" {
  name = "site-analytics"
  role = aws_iam_role.this.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid      = "WriteOwnLogGroup"
        Effect   = "Allow"
        Action   = ["logs:CreateLogStream", "logs:PutLogEvents"]
        Resource = "arn:aws:logs:${var.region}:${data.aws_caller_identity.current.account_id}:log-group:/aws/lambda/${local.function_name}:*"
      },
      {
        Sid      = "HitsAndAggregates"
        Effect   = "Allow"
        Action   = ["dynamodb:PutItem", "dynamodb:Query"]
        Resource = aws_dynamodb_table.analytics.arn
      },
      {
        Sid      = "DailySalt"
        Effect   = "Allow"
        Action   = ["dynamodb:GetItem", "dynamodb:PutItem", "dynamodb:DeleteItem"]
        Resource = aws_dynamodb_table.state.arn
      }
    ]
  })
}

data "archive_file" "this" {
  type        = "zip"
  source_file = "${path.module}/src/handler.py"
  output_path = "${path.module}/.build/site-analytics.zip"
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

  function_name    = local.function_name
  role             = aws_iam_role.this.arn
  runtime          = "python3.13"
  handler          = "handler.handler"
  architectures    = ["arm64"]
  filename         = data.archive_file.this.output_path
  source_code_hash = data.archive_file.this.output_base64sha256

  # A hit is one PutItem; a rollup reads two days of hits.
  timeout     = 60
  memory_size = 256

  # Optional cap on what a flood of fake hits can cost (excess requests are
  # throttled; the beacon doesn't retry). Off by default: an account with a
  # low concurrency quota (dev) can't reserve any. -1 = no reservation.
  reserved_concurrent_executions = var.reserved_concurrency

  environment {
    variables = {
      TABLE_NAME       = aws_dynamodb_table.analytics.name
      STATE_TABLE_NAME = aws_dynamodb_table.state.name
      SITE             = var.site
    }
  }

  tags = {
    Environment = var.environment
  }

  depends_on = [aws_cloudwatch_log_group.this]
}

resource "aws_lambda_alias" "live" {
  name             = "live"
  function_name    = aws_lambda_function.this.function_name
  function_version = aws_lambda_function.this.version
}

# AWS_IAM: only the landing distribution may call it (OAC signs every request).
resource "aws_lambda_function_url" "this" {
  function_name      = aws_lambda_function.this.function_name
  qualifier          = aws_lambda_alias.live.name
  authorization_type = "AWS_IAM"
}

# Function URLs need both permissions for the CloudFront service principal.
resource "aws_lambda_permission" "url" {
  statement_id           = "AllowLandingCloudFrontInvokeUrl"
  action                 = "lambda:InvokeFunctionUrl"
  function_name          = aws_lambda_function.this.function_name
  qualifier              = aws_lambda_alias.live.name
  principal              = "cloudfront.amazonaws.com"
  source_arn             = var.landing_distribution_arn
  function_url_auth_type = "AWS_IAM"
}

resource "aws_lambda_permission" "invoke" {
  statement_id  = "AllowLandingCloudFrontInvoke"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.this.function_name
  qualifier     = aws_lambda_alias.live.name
  principal     = "cloudfront.amazonaws.com"
  source_arn    = var.landing_distribution_arn
}

# --- rollup schedule ---------------------------------------------------------------

resource "aws_iam_role" "scheduler" {
  name = "${local.prefix}scheduler-invoke-site-analytics-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect    = "Allow"
        Principal = { Service = "scheduler.amazonaws.com" }
        Action    = "sts:AssumeRole"
        Condition = {
          StringEquals = { "aws:SourceAccount" = data.aws_caller_identity.current.account_id }
        }
      }
    ]
  })

  tags = {
    Environment = var.environment
  }
}

resource "aws_iam_role_policy" "scheduler" {
  name = "invoke-site-analytics-function"
  role = aws_iam_role.scheduler.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid      = "InvokeSiteAnalyticsFunction"
        Effect   = "Allow"
        Action   = "lambda:InvokeFunction"
        Resource = [aws_lambda_function.this.arn, "${aws_lambda_function.this.arn}:*"]
      }
    ]
  })
}

# Today's and yesterday's figures, every 15 minutes, so a visit shows on the
# Website page within a quarter of an hour.
resource "aws_scheduler_schedule" "rollup" {
  name                = "${local.function_name}-rollup"
  group_name          = "default"
  schedule_expression = var.rollup_schedule

  flexible_time_window {
    mode = "OFF"
  }

  target {
    arn      = aws_lambda_alias.live.arn
    role_arn = aws_iam_role.scheduler.arn
    input    = jsonencode({ task = "rollup" })

    retry_policy {
      maximum_retry_attempts       = 1
      maximum_event_age_in_seconds = 600
    }
  }
}

# A broken rollup or ingest shows up as errors: one email to the operators.
resource "aws_cloudwatch_metric_alarm" "errors" {
  alarm_name          = "${local.function_name}-errors"
  alarm_description   = "site-analytics (booqy.se statistics) failed more than 3 times in an hour"
  namespace           = "AWS/Lambda"
  metric_name         = "Errors"
  dimensions          = { FunctionName = aws_lambda_function.this.function_name }
  statistic           = "Sum"
  period              = 3600
  evaluation_periods  = 1
  threshold           = 3
  comparison_operator = "GreaterThanThreshold"
  treat_missing_data  = "notBreaching"
  alarm_actions       = [var.alert_topic_arn]

  tags = {
    Environment = var.environment
  }
}

# Booqy Console's Website page (platform-tenants) reads the aggregates and
# counts the last 30 minutes' visitors in the raw hits. Read only.
resource "aws_iam_role_policy" "console_read" {
  name = "site-analytics-read"
  role = var.console_role_name

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid      = "ReadSiteAnalytics"
        Effect   = "Allow"
        Action   = ["dynamodb:Query", "dynamodb:GetItem"]
        Resource = aws_dynamodb_table.analytics.arn
      }
    ]
  })
}
