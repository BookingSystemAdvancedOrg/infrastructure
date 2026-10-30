# Catering (issue 5, M2-M5): settings shared by several catering functions
# and the signing webhook's alarms. The functions, roles and routes
# themselves are in config.tf and their modules.

locals {
  # Per-object Object Lock for signed/ (and invoices/) in the documents
  # bucket, set by the writer (the bucket has no default lock, C7):
  # prod COMPLIANCE for 7 years rounded up to the end of that calendar year
  # (Bokföringslagen counts from the end of the year), dev GOVERNANCE for
  # 1 day so test data can still be cleaned up.
  catering_document_lock_env = {
    DOCUMENT_LOCK_MODE     = var.env == "prod" ? "COMPLIANCE" : "GOVERNANCE"
    DOCUMENT_LOCK_DAYS     = var.env == "prod" ? "2557" : "1"
    DOCUMENT_LOCK_YEAR_END = var.env == "prod" ? "true" : "false"
  }

  # Catering functions whose crash means a guest or the restaurant is stuck
  # (no offer PDF, no signature, no reminder or expiry, no payment recorded).
  catering_alarm_functions = {
    "catering-offer"          = module.catering_offer_fn.function_name
    "catering-customer"       = module.catering_customer_fn.function_name
    "catering-document"       = module.catering_document_fn.function_name
    "catering-lifecycle"      = module.catering_lifecycle_fn.function_name
    "catering-stripe-webhook" = module.catering_stripe_webhook_fn.function_name
  }
}

resource "aws_cloudwatch_metric_alarm" "catering_errors" {
  for_each = local.catering_alarm_functions

  alarm_name        = "${var.env == "prod" ? "" : "${var.env}-"}${each.key}-errors"
  alarm_description = "${each.key} crashed (Lambda errors). Catering requests may be stuck: check the ${each.key} logs."
  namespace         = "AWS/Lambda"
  metric_name       = "Errors"
  dimensions        = { FunctionName = each.value }

  statistic           = "Sum"
  period              = 300
  evaluation_periods  = 1
  comparison_operator = "GreaterThanThreshold"
  threshold           = 0
  treat_missing_data  = "notBreaching"

  alarm_actions = [module.alerts.topic_arn]

  tags = {
    Environment = var.env
  }
}

# The signing provider (Scrive) is down or refuses Booqy's credentials: the
# owner can't send or sign offers and guests can't sign (both answer 503
# signing_unavailable and log SIGNING_UNAVAILABLE).
resource "aws_cloudwatch_log_metric_filter" "catering_signing_unavailable" {
  for_each = {
    offer    = module.catering_offer_fn.function_name
    customer = module.catering_customer_fn.function_name
  }

  name           = "${var.env == "prod" ? "" : "${var.env}-"}catering-${each.key}-signing-unavailable"
  log_group_name = "/aws/lambda/${each.value}"
  pattern        = "SIGNING_UNAVAILABLE"

  metric_transformation {
    name          = "CateringSigningUnavailable"
    namespace     = "Booqy/${var.env}"
    value         = "1"
    default_value = "0"
  }
}

resource "aws_cloudwatch_metric_alarm" "catering_signing_unavailable" {
  alarm_name        = "${var.env == "prod" ? "" : "${var.env}-"}catering-signing-unavailable"
  alarm_description = "Catering signing failed because the signing provider could not be reached or refused Booqy's credentials (check the signing-provider secret and Scrive's status page; the catering-offer and catering-customer logs say which call)."
  namespace         = "Booqy/${var.env}"
  metric_name       = "CateringSigningUnavailable"

  statistic           = "Sum"
  period              = 300
  evaluation_periods  = 1
  comparison_operator = "GreaterThanThreshold"
  threshold           = 0
  treat_missing_data  = "notBreaching"

  alarm_actions = [module.alerts.topic_arn]
  ok_actions    = [module.alerts.topic_arn]

  tags = {
    Environment = var.env
  }

  depends_on = [aws_cloudwatch_log_metric_filter.catering_signing_unavailable]
}

# The webhook answers 5xx (and logs SIGNING_WEBHOOK_FAILED) when it
# could not process a provider callback it verified, so the provider retries;
# a crash shows as a Lambda error. Either means signatures may not reach the
# request, so someone has to look. Rejected (unverified) callbacks are not
# counted here: they are expected noise from scanners.
resource "aws_cloudwatch_log_metric_filter" "catering_signing_webhook_failed" {
  name           = "${var.env == "prod" ? "" : "${var.env}-"}catering-signing-webhook-failed"
  log_group_name = "/aws/lambda/${module.catering_signing_webhook_fn.function_name}"
  pattern        = "SIGNING_WEBHOOK_FAILED"

  metric_transformation {
    name          = "CateringSigningWebhookFailed"
    namespace     = "Booqy/${var.env}"
    value         = "1"
    default_value = "0"
  }
}

resource "aws_cloudwatch_metric_alarm" "catering_signing_webhook_failed" {
  alarm_name        = "${var.env == "prod" ? "" : "${var.env}-"}catering-signing-webhook-failed"
  alarm_description = "The catering signing webhook could not process a verified provider callback (the provider retries). Signatures may not reach the request: check the catering-signing-webhook logs."
  namespace         = "Booqy/${var.env}"
  metric_name       = "CateringSigningWebhookFailed"

  statistic           = "Sum"
  period              = 300
  evaluation_periods  = 1
  comparison_operator = "GreaterThanThreshold"
  threshold           = 0
  treat_missing_data  = "notBreaching"

  alarm_actions = [module.alerts.topic_arn]
  ok_actions    = [module.alerts.topic_arn]

  tags = {
    Environment = var.env
  }

  depends_on = [aws_cloudwatch_log_metric_filter.catering_signing_webhook_failed]
}

resource "aws_cloudwatch_metric_alarm" "catering_signing_webhook_errors" {
  alarm_name        = "${var.env == "prod" ? "" : "${var.env}-"}catering-signing-webhook-errors"
  alarm_description = "The catering signing webhook Lambda crashed. Provider callbacks are retried by the provider, but signatures may not reach the request: check the catering-signing-webhook logs."
  namespace         = "AWS/Lambda"
  metric_name       = "Errors"
  dimensions        = { FunctionName = module.catering_signing_webhook_fn.function_name }

  statistic           = "Sum"
  period              = 300
  evaluation_periods  = 1
  comparison_operator = "GreaterThanThreshold"
  threshold           = 0
  treat_missing_data  = "notBreaching"

  alarm_actions = [module.alerts.topic_arn]

  tags = {
    Environment = var.env
  }
}
