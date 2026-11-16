# Stripe webhooks: each is served on its own Lambda Function URL (not the
# HTTP API), and answers a bad signature with 400 and a failure it wants
# Stripe to retry with 500. Both are handled responses, so Lambda Errors
# stays 0 and no API alarm sees them. The Function URL metrics count the
# status code the caller got (a crash or timeout shows as 5xx too). Stripe
# retries for 3 days, then disables the endpoint.
#
# 5xx: any in 5 minutes. 4xx: at least 3 in 15 minutes (a wrong or rotated
# signing secret fails every event; a stray probe or a 404/405 does not).

locals {
  stripe_webhooks = {
    "stripe-webhook"          = { function_name = module.stripe_webhook_fn.function_name, records = "booking payments and refunds" }
    "webhook-payment-intent"  = { function_name = module.webhook_payment_intent_fn.function_name, records = "order payments and refunds" }
    "catering-stripe-webhook" = { function_name = module.catering_stripe_webhook_fn.function_name, records = "catering payments" }
    "platform-stripe-webhook" = { function_name = module.platform_stripe_webhook_fn.function_name, records = "Connect accounts and subscription invoices" }
  }
}

resource "aws_cloudwatch_metric_alarm" "stripe_webhook_5xx" {
  for_each = local.stripe_webhooks

  alarm_name        = "${each.value.function_name}-url-5xx"
  alarm_description = "${each.key} answered Stripe with 5xx (secret or table unavailable, a feature hook failing, or a crash). Stripe retries, but ${each.value.records} are not recorded until it succeeds: check the ${each.key} logs."
  namespace         = "AWS/Lambda"
  metric_name       = "Url5xxCount"
  dimensions        = { FunctionName = each.value.function_name }

  statistic           = "Sum"
  period              = 300
  evaluation_periods  = 1
  comparison_operator = "GreaterThanOrEqualToThreshold"
  threshold           = 1
  treat_missing_data  = "notBreaching"

  alarm_actions = [module.alerts.topic_arn]
  ok_actions    = [module.alerts.topic_arn]

  tags = {
    Environment = var.env
  }
}

resource "aws_cloudwatch_metric_alarm" "stripe_webhook_4xx" {
  for_each = local.stripe_webhooks

  alarm_name        = "${each.value.function_name}-url-4xx"
  alarm_description = "${each.key} rejected requests with 4xx, most likely invalid signatures: the signing secret in Secrets Manager may not match the endpoint in Stripe. Until fixed, ${each.value.records} are not recorded, and Stripe disables the endpoint after 3 days of failures."
  namespace         = "AWS/Lambda"
  metric_name       = "Url4xxCount"
  dimensions        = { FunctionName = each.value.function_name }

  statistic           = "Sum"
  period              = 900
  evaluation_periods  = 1
  comparison_operator = "GreaterThanOrEqualToThreshold"
  threshold           = 3
  treat_missing_data  = "notBreaching"

  alarm_actions = [module.alerts.topic_arn]
  ok_actions    = [module.alerts.topic_arn]

  tags = {
    Environment = var.env
  }
}
