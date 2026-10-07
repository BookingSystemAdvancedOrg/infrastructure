# Blue/green releases for every container-image Lambda.
#
# How a release works (driven by ci/lambda-release.sh, called from the app
# repos' pipelines and from this repo's pipeline after an apply):
#   1. new code lands on $LATEST and is published as version N (green)
#   2. a CodeDeploy deployment shifts the "live" alias from the current
#      version (blue) to N, using aws_codedeploy_deployment_config.lambda:
#        prod - 10% for 5 minutes, then 100%
#        dev  - all at once (no alarms in dev - see var.rollback_alarms_enabled)
#   3. prod only: while traffic shifts, CodeDeploy watches the two alarms
#      below for that function; if either goes into ALARM the alias is moved
#      back to blue automatically and the release fails. In every
#      environment a deployment that fails outright is rolled back too.
#   4. the release script emails the outcome (success / rolled back) to the
#      platform alerts topic
#
# Terraform owns the CodeDeploy plumbing only - it never moves an alias
# (see compute/lambda/*/alias.tf).

data "aws_caller_identity" "current" {}

locals {
  prefix     = var.environment == "prod" ? "" : "${var.environment}-"
  shift_name = var.traffic_shift_type == "AllAtOnce" ? "all-at-once" : "${var.traffic_shift_type == "TimeBasedCanary" ? "canary" : "linear"}-${var.traffic_shift_percentage}pct-${var.traffic_shift_interval_minutes}min"

  # Alarms cost money per month whether or not anything is deployed, so
  # they exist only where they protect real users (prod).
  alarmed_functions = var.rollback_alarms_enabled ? var.functions : {}
}

resource "aws_codedeploy_app" "lambda" {
  name             = "${local.prefix}lambda-releases"
  compute_platform = "Lambda"

  tags = {
    Environment = var.environment
  }
}

# How traffic moves from blue to green (custom, so the canary/linear
# percentage and interval are set from config.tf).
resource "aws_codedeploy_deployment_config" "lambda" {
  deployment_config_name = "${local.prefix}lambda-${local.shift_name}"
  compute_platform       = "Lambda"

  traffic_routing_config {
    type = var.traffic_shift_type

    dynamic "time_based_canary" {
      for_each = var.traffic_shift_type == "TimeBasedCanary" ? [1] : []
      content {
        percentage = var.traffic_shift_percentage
        interval   = var.traffic_shift_interval_minutes
      }
    }

    dynamic "time_based_linear" {
      for_each = var.traffic_shift_type == "TimeBasedLinear" ? [1] : []
      content {
        percentage = var.traffic_shift_percentage
        interval   = var.traffic_shift_interval_minutes
      }
    }
  }

  # Configs can't be changed in place; the replacement must exist before the
  # deployment groups are pointed at it.
  lifecycle {
    create_before_destroy = true
  }
}

# ---------- service role ----------

resource "aws_iam_role" "codedeploy" {
  name = "${local.prefix}lambda-releases-codedeploy-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect    = "Allow"
        Principal = { Service = "codedeploy.amazonaws.com" }
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

# AWS-managed: read/update aliases, read alarms, publish to SNS - exactly
# what a Lambda traffic shift needs.
resource "aws_iam_role_policy_attachment" "codedeploy" {
  role       = aws_iam_role.codedeploy.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AWSCodeDeployRoleForLambdaLimited"
}

# ---------- rollback alarms (per function, on the live alias only) ----------
#
# Both alarms look at the "live" alias (dimension Resource = <fn>:live), so
# they measure exactly the traffic being shifted. 1-minute periods so they
# can fire inside the canary window. Missing data (no traffic) counts as
# healthy - a quiet function is not a broken one.

resource "aws_cloudwatch_metric_alarm" "error_rate" {
  for_each = local.alarmed_functions

  alarm_name          = "${each.key}-live-error-rate"
  alarm_description   = "Error rate on ${each.key}:live above ${var.error_rate_threshold_percent}% (with at least ${var.min_errors} errors in a minute). Fails/rolls back a release in progress."
  comparison_operator = "GreaterThanThreshold"
  threshold           = var.error_rate_threshold_percent
  evaluation_periods  = 1
  datapoints_to_alarm = 1
  treat_missing_data  = "notBreaching"
  alarm_actions       = [var.alert_topic_arn]
  ok_actions          = [var.alert_topic_arn]

  metric_query {
    id          = "rate"
    expression  = "IF(errors >= ${var.min_errors} AND invocations > 0, 100 * errors / invocations, 0)"
    label       = "Error rate (%)"
    return_data = true
  }

  metric_query {
    id = "errors"
    metric {
      namespace   = "AWS/Lambda"
      metric_name = "Errors"
      period      = 60
      stat        = "Sum"
      dimensions = {
        FunctionName = each.key
        Resource     = "${each.key}:${each.value.alias_name}"
      }
    }
  }

  metric_query {
    id = "invocations"
    metric {
      namespace   = "AWS/Lambda"
      metric_name = "Invocations"
      period      = 60
      stat        = "Sum"
      dimensions = {
        FunctionName = each.key
        Resource     = "${each.key}:${each.value.alias_name}"
      }
    }
  }

  tags = {
    Environment = var.environment
  }
}

resource "aws_cloudwatch_metric_alarm" "throttles" {
  for_each = local.alarmed_functions

  alarm_name          = "${each.key}-live-throttles"
  alarm_description   = "${each.key}:live is being throttled. Fails/rolls back a release in progress."
  namespace           = "AWS/Lambda"
  metric_name         = "Throttles"
  statistic           = "Sum"
  period              = 60
  comparison_operator = "GreaterThanOrEqualToThreshold"
  threshold           = var.throttle_threshold
  evaluation_periods  = 1
  datapoints_to_alarm = 1
  treat_missing_data  = "notBreaching"
  alarm_actions       = [var.alert_topic_arn]
  ok_actions          = [var.alert_topic_arn]

  dimensions = {
    FunctionName = each.key
    Resource     = "${each.key}:${each.value.alias_name}"
  }

  tags = {
    Environment = var.environment
  }
}

# ---------- one deployment group per function ----------

resource "aws_codedeploy_deployment_group" "this" {
  for_each = var.functions

  app_name               = aws_codedeploy_app.lambda.name
  deployment_group_name  = each.key
  service_role_arn       = aws_iam_role.codedeploy.arn
  deployment_config_name = aws_codedeploy_deployment_config.lambda.id

  deployment_style {
    deployment_type   = "BLUE_GREEN"
    deployment_option = "WITH_TRAFFIC_CONTROL"
  }

  auto_rollback_configuration {
    enabled = true
    events  = var.rollback_alarms_enabled ? ["DEPLOYMENT_FAILURE", "DEPLOYMENT_STOP_ON_ALARM"] : ["DEPLOYMENT_FAILURE"]
  }

  dynamic "alarm_configuration" {
    for_each = var.rollback_alarms_enabled ? [1] : []
    content {
      enabled = true
      alarms = [
        aws_cloudwatch_metric_alarm.error_rate[each.key].alarm_name,
        aws_cloudwatch_metric_alarm.throttles[each.key].alarm_name,
      ]
    }
  }

  tags = {
    Environment = var.environment
  }
}
