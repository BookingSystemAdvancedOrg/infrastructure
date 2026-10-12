# Alerting for the platform's asynchronous failure paths (dead-letter queues
# in storage/sqs/dead-letter). Two sources publish to one SNS topic (email):
#
#   1. dlq-replay, directly - when a DLQ message has failed
#      MAX_REPLAY_ATTEMPTS replays and needs a person (bug or bad data),
#      or when emails may have been lost (expired notification records).
#   2. The CloudWatch alarms below - the safety net for when the replay
#      itself isn't doing its job:
#        - a DLQ message has been sitting for more than two replay
#          intervals (replay not running, or stuck on it),
#        - the replay Lambda itself is erroring.
#
# Alarms deliberately don't fire on "a message arrived in a DLQ": arrivals
# are expected occasionally and the scheduled replay handles most of them
# without anyone needing to look.
#
# Messaging guardrails (bottom of the file): the account's SMS spend limit
# with an alarm before it is reached, and SES reputation alarms - a bounce
# or complaint rate that keeps rising gets the account's email paused by
# AWS, for every restaurant at once.

data "aws_caller_identity" "current" {}

locals {
  prefix = var.environment == "prod" ? "" : "${var.environment}-"
  # Two full replay cycles plus 10 minutes of slack, in seconds.
  stuck_after_seconds = var.replay_interval_minutes * 60 * 2 + 600
}

resource "aws_sns_topic" "alerts" {
  name = "${local.prefix}platform-alerts"

  tags = {
    Environment = var.environment
  }
}

# Same-account principals (the replay Lambda's role) publish via their own
# IAM policy; CloudWatch alarms in this account publish via the second
# statement, scoped to alarms in this account.
resource "aws_sns_topic_policy" "alerts" {
  arn = aws_sns_topic.alerts.arn

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid       = "AllowAccountPrincipals"
        Effect    = "Allow"
        Principal = { AWS = "arn:aws:iam::${data.aws_caller_identity.current.account_id}:root" }
        Action    = ["sns:Publish", "sns:Subscribe", "sns:GetTopicAttributes"]
        Resource  = "${aws_sns_topic.alerts.arn}"
      },
      {
        Sid       = "AllowCloudWatchAlarms"
        Effect    = "Allow"
        Principal = { Service = "cloudwatch.amazonaws.com" }
        Action    = "sns:Publish"
        Resource  = "${aws_sns_topic.alerts.arn}"
        Condition = {
          ArnLike = { "aws:SourceArn" = "arn:aws:cloudwatch:${var.region}:${data.aws_caller_identity.current.account_id}:alarm:*" }
        }
      }
    ]
  })
}

# Each address gets a confirmation email from AWS after the first apply and
# receives nothing until the link in it is clicked.
resource "aws_sns_topic_subscription" "email" {
  for_each = toset(var.alert_emails)

  topic_arn = aws_sns_topic.alerts.arn
  protocol  = "email"
  endpoint  = each.value
}

resource "aws_cloudwatch_metric_alarm" "dlq_stuck" {
  for_each = var.dlq_queue_names

  alarm_name        = "${each.value}-stuck"
  alarm_description = "A message has been in ${each.value} for more than two replay intervals - dlq-replay is not clearing it. Check the replay Lambda's logs."
  namespace         = "AWS/SQS"
  metric_name       = "ApproximateAgeOfOldestMessage"
  dimensions        = { QueueName = each.value }

  statistic           = "Maximum"
  period              = 300
  evaluation_periods  = 1
  comparison_operator = "GreaterThanThreshold"
  threshold           = local.stuck_after_seconds
  treat_missing_data  = "notBreaching"

  alarm_actions = ["${aws_sns_topic.alerts.arn}"]
  ok_actions    = ["${aws_sns_topic.alerts.arn}"]

  tags = {
    Environment = var.environment
  }
}

resource "aws_cloudwatch_metric_alarm" "replay_errors" {
  alarm_name        = "${local.prefix}dlq-replay-errors"
  alarm_description = "The dlq-replay Lambda itself failed - failed background work is not being redelivered."
  namespace         = "AWS/Lambda"
  metric_name       = "Errors"
  dimensions        = { FunctionName = var.replay_function_name }

  statistic           = "Sum"
  period              = 300
  evaluation_periods  = 1
  comparison_operator = "GreaterThanThreshold"
  threshold           = 0
  treat_missing_data  = "notBreaching"

  alarm_actions = ["${aws_sns_topic.alerts.arn}"]

  tags = {
    Environment = var.environment
  }
}

# --- messaging guardrails -------------------------------------------------------

# Account-wide SMS settings in this region, managed only when the
# environment sets sms_monthly_spend_limit_usd (otherwise the account's
# current settings are left as they are). monthly_spend_limit can't exceed
# the account's SMS quota (new accounts: 1 USD) - raise the quota with an
# AWS support case first, then this variable. When the limit is reached SNS
# stops sending SMS for the rest of the month (the e-mails still go out).
resource "aws_sns_sms_preferences" "this" {
  count = var.sms_monthly_spend_limit_usd == null ? 0 : 1

  monthly_spend_limit = var.sms_monthly_spend_limit_usd
  default_sms_type    = "Transactional"
}

resource "aws_cloudwatch_metric_alarm" "sms_spend" {
  count = var.sms_monthly_spend_limit_usd == null ? 0 : 1

  alarm_name        = "${local.prefix}sms-spend-near-limit"
  alarm_description = "SMS spend this month has passed 80% of the account's monthly limit (${var.sms_monthly_spend_limit_usd} USD). At the limit SNS stops sending SMS until next month - raise the quota (support case) and sms_monthly_spend_limit_usd, or look for abuse."
  namespace         = "AWS/SNS"
  metric_name       = "SMSMonthToDateSpentUSD"

  statistic           = "Maximum"
  period              = 3600
  evaluation_periods  = 1
  comparison_operator = "GreaterThanOrEqualToThreshold"
  threshold           = var.sms_monthly_spend_limit_usd * 0.8
  treat_missing_data  = "notBreaching"

  alarm_actions = ["${aws_sns_topic.alerts.arn}"]

  tags = {
    Environment = var.environment
  }
}

# AWS reviews an account at 5 % bounces / 0.1 % complaints and may pause
# sending at 10 % / 0.5 %. These fire well before the review level.
resource "aws_cloudwatch_metric_alarm" "ses_bounce_rate" {
  alarm_name        = "${local.prefix}ses-bounce-rate"
  alarm_description = "SES bounce rate is above 4% - AWS reviews the account at 5% and can pause email for every restaurant. Look for bookings with fake addresses."
  namespace         = "AWS/SES"
  metric_name       = "Reputation.BounceRate"

  statistic           = "Maximum"
  period              = 3600
  evaluation_periods  = 1
  comparison_operator = "GreaterThanThreshold"
  threshold           = 0.04
  treat_missing_data  = "notBreaching"

  alarm_actions = ["${aws_sns_topic.alerts.arn}"]
  ok_actions    = ["${aws_sns_topic.alerts.arn}"]

  tags = {
    Environment = var.environment
  }
}

resource "aws_cloudwatch_metric_alarm" "ses_complaint_rate" {
  alarm_name        = "${local.prefix}ses-complaint-rate"
  alarm_description = "SES complaint rate is above 0.08% - AWS reviews the account at 0.1% and can pause email for every restaurant."
  namespace         = "AWS/SES"
  metric_name       = "Reputation.ComplaintRate"

  statistic           = "Maximum"
  period              = 3600
  evaluation_periods  = 1
  comparison_operator = "GreaterThanThreshold"
  threshold           = 0.0008
  treat_missing_data  = "notBreaching"

  alarm_actions = ["${aws_sns_topic.alerts.arn}"]
  ok_actions    = ["${aws_sns_topic.alerts.arn}"]

  tags = {
    Environment = var.environment
  }
}
