# Uptime check: a small Lambda (uptime/handler.py, zipped from this repo like
# pre-token-generation) runs every 5 minutes, loads the customer site and
# the admin app and calls GET /site-config, and reports each check as a
# CloudWatch metric (Booqy/Uptime, CheckFailed = 0 or 1 per check). One alarm
# per check emails the alerts topic when two of the last three runs failed,
# and again when it recovers.
#
# Chosen over a CloudWatch Synthetics canary on cost: a canary every 5
# minutes is about 10 USD a month per environment before its Lambda and S3
# charges; this is a few invocations, two custom metrics and three alarms,
# about 1 USD. What it loses - a real browser - the smoke tests in the
# pipelines cover at deploy time (ci/smoke-test.sh checks that the page's
# script bundle is served).
#
# IAM (new execution role, nothing else touched): write its own log group,
# and cloudwatch:PutMetricData restricted to the Booqy/Uptime namespace.

locals {
  uptime_function_name = "${local.prefix}uptime-check"
  uptime_namespace     = "Booqy/Uptime"

  # What is checked. The site-config check proves API Gateway -> Lambda ->
  # DynamoDB end to end: with a known restaurant host it must answer 200 with
  # the tenant; without one (prod until a test restaurant exists) an unknown
  # host must answer the handler's own 404, which is only reached after the
  # lookup.
  uptime_checks = var.uptime_check_enabled ? {
    customer-site = {
      url           = var.customer_site_url
      expect_status = 200
      expect_body   = "id=\"root\""
    }
    admin-app = {
      url           = var.admin_app_url
      expect_status = 200
      expect_body   = "id=\"root\""
    }
    site-config = var.smoke_test_host != "" ? {
      url           = "${trimsuffix(var.api_endpoint, "/")}/site-config?host=${var.smoke_test_host}"
      expect_status = 200
      expect_body   = "\"tenantId\""
      } : {
      url           = "${trimsuffix(var.api_endpoint, "/")}/site-config?host=smoke-test.invalid"
      expect_status = 404
      expect_body   = "not found"
    }
  } : {}
}

data "archive_file" "uptime" {
  type        = "zip"
  source_file = "${path.module}/uptime/handler.py"
  output_path = "${path.module}/.build/uptime-check.zip"
}

resource "aws_cloudwatch_log_group" "uptime" {
  count = var.uptime_check_enabled ? 1 : 0

  name              = "/aws/lambda/${local.uptime_function_name}"
  retention_in_days = 30

  tags = {
    Environment = var.environment
  }
}

resource "aws_iam_role" "uptime" {
  count = var.uptime_check_enabled ? 1 : 0

  name = "${local.uptime_function_name}-role"

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

resource "aws_iam_role_policy" "uptime" {
  count = var.uptime_check_enabled ? 1 : 0

  name = "uptime-check"
  role = aws_iam_role.uptime[0].id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid    = "WriteOwnLogGroup"
        Effect = "Allow"
        Action = [
          "logs:CreateLogStream",
          "logs:PutLogEvents",
        ]
        Resource = "${aws_cloudwatch_log_group.uptime[0].arn}:*"
      },
      {
        Sid      = "PublishUptimeMetricsOnly"
        Effect   = "Allow"
        Action   = "cloudwatch:PutMetricData"
        Resource = "*"
        Condition = {
          StringEquals = { "cloudwatch:namespace" = local.uptime_namespace }
        }
      }
    ]
  })
}

resource "aws_lambda_function" "uptime" {
  count = var.uptime_check_enabled ? 1 : 0

  function_name    = local.uptime_function_name
  role             = aws_iam_role.uptime[0].arn
  runtime          = "python3.13"
  handler          = "handler.handler"
  architectures    = ["arm64"]
  filename         = data.archive_file.uptime.output_path
  source_code_hash = data.archive_file.uptime.output_base64sha256
  timeout          = 45
  memory_size      = 128

  environment {
    variables = {
      CHECKS           = jsonencode([for name, c in local.uptime_checks : merge({ name = name }, c)])
      METRIC_NAMESPACE = local.uptime_namespace
      ENVIRONMENT      = var.environment
    }
  }

  tags = {
    Environment = var.environment
  }

  depends_on = [aws_cloudwatch_log_group.uptime, aws_iam_role_policy.uptime]
}

resource "aws_cloudwatch_event_rule" "uptime" {
  count = var.uptime_check_enabled ? 1 : 0

  name                = "${local.uptime_function_name}-every-5-minutes"
  description         = "Runs the uptime check (customer site, admin app, GET /site-config)"
  schedule_expression = "rate(5 minutes)"

  tags = {
    Environment = var.environment
  }
}

resource "aws_cloudwatch_event_target" "uptime" {
  count = var.uptime_check_enabled ? 1 : 0

  rule = aws_cloudwatch_event_rule.uptime[0].name
  arn  = aws_lambda_function.uptime[0].arn
}

resource "aws_lambda_permission" "uptime" {
  count = var.uptime_check_enabled ? 1 : 0

  statement_id  = "AllowEventBridgeSchedule"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.uptime[0].function_name
  principal     = "events.amazonaws.com"
  source_arn    = aws_cloudwatch_event_rule.uptime[0].arn
}

# One alarm per check. Missing data is healthy here so a fresh alarm does
# not page before the first run; the checker itself failing is the alarm
# below.
resource "aws_cloudwatch_metric_alarm" "uptime" {
  for_each = local.uptime_checks

  alarm_name          = "${local.prefix}uptime-${each.key}"
  alarm_description   = "${each.key} failed the uptime check in two of the last three runs: ${each.value.url} did not answer ${each.value.expect_status} with the expected content. The check runs every 5 minutes from ${local.uptime_function_name}; its log shows the status and body it got. See docs/RELEASES.md."
  namespace           = local.uptime_namespace
  metric_name         = "CheckFailed"
  dimensions          = { Check = each.key }
  statistic           = "Maximum"
  period              = 300
  comparison_operator = "GreaterThanOrEqualToThreshold"
  threshold           = 1
  evaluation_periods  = 3
  datapoints_to_alarm = 2
  treat_missing_data  = "notBreaching"
  alarm_actions       = [aws_sns_topic.alerts.arn]
  ok_actions          = [aws_sns_topic.alerts.arn]

  tags = {
    Environment = var.environment
  }
}

resource "aws_cloudwatch_metric_alarm" "uptime_errors" {
  count = var.uptime_check_enabled ? 1 : 0

  alarm_name          = "${local.prefix}uptime-check-errors"
  alarm_description   = "The uptime-check Lambda itself failed (it could not even report its checks) - the site alarms are blind until it runs again. Check its log."
  namespace           = "AWS/Lambda"
  metric_name         = "Errors"
  dimensions          = { FunctionName = local.uptime_function_name }
  statistic           = "Sum"
  period              = 300
  comparison_operator = "GreaterThanThreshold"
  threshold           = 0
  evaluation_periods  = 2
  datapoints_to_alarm = 2
  treat_missing_data  = "notBreaching"
  alarm_actions       = [aws_sns_topic.alerts.arn]

  tags = {
    Environment = var.environment
  }
}
