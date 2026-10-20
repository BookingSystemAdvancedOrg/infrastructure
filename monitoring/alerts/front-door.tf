# Front-door alarms: what guests and restaurants hit first. The Lambda
# alarms (orchestration/lambda-releases) see a function that errors; these
# see a release that is wrong one layer up - an API Gateway integration that
# never reaches a Lambda, a route that disappeared, a CloudFront origin that
# points at an empty bucket - and the slow failures (p99 latency) that no
# error counter shows. All of them email the alerts topic; the CloudFront
# ones through its us-east-1 twin (see providers.tf).
#
# Thresholds are rates with a minimum request count, so one failed request
# at night does not page anyone.

# ---------- API Gateway (HTTP API) ----------

resource "aws_cloudwatch_metric_alarm" "api_5xx_rate" {
  alarm_name          = "${local.prefix}api-5xx-rate"
  alarm_description   = "More than ${var.api_5xx_threshold_percent}% of API requests (${var.api_name}) answered 5xx in 5 minutes, with at least ${var.api_min_errors} errors. A release is broken at the API or integration level (the Lambda alarms may not fire: a missing integration never invokes one). See docs/RELEASES.md."
  comparison_operator = "GreaterThanThreshold"
  threshold           = var.api_5xx_threshold_percent
  evaluation_periods  = 1
  datapoints_to_alarm = 1
  treat_missing_data  = "notBreaching"
  alarm_actions       = [aws_sns_topic.alerts.arn]
  ok_actions          = [aws_sns_topic.alerts.arn]

  metric_query {
    id          = "rate"
    expression  = "IF(errors >= ${var.api_min_errors} AND requests > 0, 100 * errors / requests, 0)"
    label       = "5xx rate (%)"
    return_data = true
  }

  metric_query {
    id = "errors"
    metric {
      namespace   = "AWS/ApiGateway"
      metric_name = "5xx"
      period      = 300
      stat        = "Sum"
      dimensions  = { ApiId = var.api_id }
    }
  }

  metric_query {
    id = "requests"
    metric {
      namespace   = "AWS/ApiGateway"
      metric_name = "Count"
      period      = 300
      stat        = "Sum"
      dimensions  = { ApiId = var.api_id }
    }
  }

  tags = {
    Environment = var.environment
  }
}

# p99 over 5 minutes: cold starts of the container-image Lambdas are a few
# seconds, so the threshold sits above them and two of three periods must
# breach - a release that doubled every response time, not a single cold
# start.
resource "aws_cloudwatch_metric_alarm" "api_p99_latency" {
  alarm_name          = "${local.prefix}api-p99-latency"
  alarm_description   = "p99 latency of the API (${var.api_name}) above ${var.api_p99_latency_threshold_ms} ms for 10 of the last 15 minutes. Slow Lambda, a throttled table, or an external call (Stripe, SES) hanging - check the Lambda durations. See docs/RELEASES.md."
  namespace           = "AWS/ApiGateway"
  metric_name         = "Latency"
  dimensions          = { ApiId = var.api_id }
  extended_statistic  = "p99"
  period              = 300
  unit                = "Milliseconds"
  comparison_operator = "GreaterThanThreshold"
  threshold           = var.api_p99_latency_threshold_ms
  evaluation_periods  = 3
  datapoints_to_alarm = 2
  treat_missing_data  = "notBreaching"
  alarm_actions       = [aws_sns_topic.alerts.arn]
  ok_actions          = [aws_sns_topic.alerts.arn]

  tags = {
    Environment = var.environment
  }
}

# ---------- CloudFront (us-east-1) ----------

# Twin of the main topic for alarms that must live in us-east-1. Same
# addresses - each gets one more confirmation email from AWS after the
# first apply.
resource "aws_sns_topic" "alerts_us_east_1" {
  provider = aws.us_east_1
  name     = "${local.prefix}platform-alerts-us-east-1"

  tags = {
    Environment = var.environment
  }
}

resource "aws_sns_topic_policy" "alerts_us_east_1" {
  provider = aws.us_east_1
  arn      = aws_sns_topic.alerts_us_east_1.arn

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid       = "AllowAccountPrincipals"
        Effect    = "Allow"
        Principal = { AWS = "arn:aws:iam::${data.aws_caller_identity.current.account_id}:root" }
        Action    = ["sns:Publish", "sns:Subscribe", "sns:GetTopicAttributes"]
        Resource  = aws_sns_topic.alerts_us_east_1.arn
      },
      {
        Sid       = "AllowCloudWatchAlarms"
        Effect    = "Allow"
        Principal = { Service = "cloudwatch.amazonaws.com" }
        Action    = "sns:Publish"
        Resource  = aws_sns_topic.alerts_us_east_1.arn
        Condition = {
          ArnLike = { "aws:SourceArn" = "arn:aws:cloudwatch:us-east-1:${data.aws_caller_identity.current.account_id}:alarm:*" }
        }
      }
    ]
  })
}

resource "aws_sns_topic_subscription" "email_us_east_1" {
  provider = aws.us_east_1
  for_each = toset(var.alert_emails)

  topic_arn = aws_sns_topic.alerts_us_east_1.arn
  protocol  = "email"
  endpoint  = each.value
}

# 5xxErrorRate is one of CloudFront's default (free) metrics. A 5xx from
# CloudFront means the origin failed: an S3 bucket a deploy emptied, the API
# behind the admin app's /api proxy, or a missing index.html. The rate only
# counts once the distribution saw var.cloudfront_min_requests requests in
# the period.
resource "aws_cloudwatch_metric_alarm" "cloudfront_5xx_rate" {
  provider = aws.us_east_1
  for_each = var.cloudfront_distributions

  alarm_name          = "${local.prefix}cloudfront-${each.key}-5xx-rate"
  alarm_description   = "More than ${var.cloudfront_5xx_threshold_percent}% of requests to the ${each.key} distribution (${each.value}) got a 5xx for 10 minutes. The origin is failing: an emptied bucket after a bad frontend deploy, or the API behind the admin app. Redeploy the previous commit (docs/RELEASES.md)."
  comparison_operator = "GreaterThanThreshold"
  threshold           = var.cloudfront_5xx_threshold_percent
  evaluation_periods  = 2
  datapoints_to_alarm = 2
  treat_missing_data  = "notBreaching"
  alarm_actions       = [aws_sns_topic.alerts_us_east_1.arn]
  ok_actions          = [aws_sns_topic.alerts_us_east_1.arn]

  metric_query {
    id          = "gated"
    expression  = "IF(requests >= ${var.cloudfront_min_requests}, rate, 0)"
    label       = "5xx rate (%)"
    return_data = true
  }

  metric_query {
    id = "rate"
    metric {
      namespace   = "AWS/CloudFront"
      metric_name = "5xxErrorRate"
      period      = 300
      stat        = "Average"
      dimensions = {
        DistributionId = each.value
        Region         = "Global"
      }
    }
  }

  metric_query {
    id = "requests"
    metric {
      namespace   = "AWS/CloudFront"
      metric_name = "Requests"
      period      = 300
      stat        = "Sum"
      dimensions = {
        DistributionId = each.value
        Region         = "Global"
      }
    }
  }

  tags = {
    Environment = var.environment
  }
}
