# Scheduled jobs: any failed run (an exception, a timeout or an OOM) emails
# the operators. The live error-rate alarm (orchestration/lambda-releases)
# needs 3 errors in one minute, which a job run every 15 minutes or once a
# night never reaches, and these jobs have no Lambda retries.
#
# FunctionName alone sums all versions and aliases. Lambda timestamps a
# datapoint at the start of the invocation, so a run that times out lands
# up to `timeout` seconds in the past: the window covers that.

locals {
  scheduled_jobs = {
    "reservation-reminders" = {
      function_name = module.reservation_reminders_fn.function_name
      timeout       = 300
      action        = "Guests may not be getting booking reminders. Check its logs; the next run (every 15 minutes) retries."
    }
    "data-retention" = {
      function_name = module.data_retention_fn.function_name
      timeout       = 900
      action        = "Personal data past its retention period may not have been removed. Check its logs; the next nightly run continues."
    }
    "tenant-purge" = {
      function_name = module.tenant_purge_fn.function_name
      timeout       = 900
      action        = "Offboarded restaurants' data may not have been purged. Check its logs; the next run continues."
    }
    "insights-rollup" = {
      function_name = module.insights_rollup_fn.function_name
      timeout       = 900
      action        = "Statistik in the admin app may be out of date. Check its logs; the next nightly run recomputes the last days."
    }
    "finance-rollup" = {
      function_name = module.finance_rollup_fn.function_name
      timeout       = 900
      action        = "Finance figures may be missing a day. Check its logs; Rebuild in Booqy Console reruns a date range."
    }
    "marketing-send" = {
      function_name = module.marketing.function_names["marketing-send"]
      timeout       = 300
      action        = "Due campaigns may not be sending. Check its logs; the next run (every 2 minutes) continues."
    }
  }
}

resource "aws_cloudwatch_metric_alarm" "scheduled_job_errors" {
  for_each = local.scheduled_jobs

  alarm_name        = "${each.value.function_name}-errors"
  alarm_description = "${each.key} failed (an exception, a timeout or out of memory). ${each.value.action}"
  namespace         = "AWS/Lambda"
  metric_name       = "Errors"
  dimensions        = { FunctionName = each.value.function_name }

  statistic           = "Sum"
  period              = 300
  evaluation_periods  = ceil(each.value.timeout / 300) + 1
  datapoints_to_alarm = 1
  comparison_operator = "GreaterThanOrEqualToThreshold"
  threshold           = 1
  treat_missing_data  = "notBreaching"

  alarm_actions = [module.alerts.topic_arn]
  ok_actions    = [module.alerts.topic_arn]

  tags = {
    Environment = var.env
  }
}
