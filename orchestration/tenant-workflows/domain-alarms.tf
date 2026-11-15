# Own domains: alarms (owner 2026-11-15). Every alarm goes to the alert topic.
#
# 1. A domain workflow that stops without saying so: domain-provision,
#    domain-attach and domain-detach executions that TIMED_OUT or were
#    ABORTED (a FAILED one already sends its own alert from NotifyFailure).
# 2. The daily domain health check (platform-tenants {"domainTask":
#    "health"}, prod; scheduled in compute/lambda/platform-tenants) puts Booqy/Domains metrics: registered domains that
#    expire within 30 days, failed Route 53 Domains operations (renewals,
#    transfers, registrations) since the last run, domains whose auto-renew
#    is off while a customer still uses them, and registrant e-mails ICANN
#    still waits to have confirmed (unconfirmed for 15 days = suspended).
locals {
  domain_state_machines = [for k in ["domain_provision", "domain_attach", "domain_detach"] : local.state_machine_arns[k]]
  domain_metrics = {
    ExpiringUnder30Days = "A registered domain expires within 30 days - its renewal has not gone through (Route 53 console, Registered domains)"
    FailedOperations    = "A Route 53 Domains operation failed (renewal, registration or transfer) - see the operation in the Route 53 console"
    AutoRenewOff        = "Auto-renew is off for a domain a customer still uses - switch it on in the Route 53 console"
    ReachabilityPending = "A registrant has not confirmed the ICANN e-mail - the domain is suspended 15 days after registration without it"
  }
}

resource "aws_cloudwatch_event_rule" "domain_workflows_stopped" {
  name        = "${local.prefix}domain-workflows-stopped"
  description = "Own domains: a domain workflow timed out or was aborted"
  event_pattern = jsonencode({
    source      = ["aws.states"]
    detail-type = ["Step Functions Execution Status Change"]
    detail = {
      status          = ["TIMED_OUT", "ABORTED"]
      stateMachineArn = local.domain_state_machines
    }
  })

  tags = {
    Environment = var.environment
  }
}

resource "aws_cloudwatch_event_target" "domain_workflows_stopped" {
  rule      = aws_cloudwatch_event_rule.domain_workflows_stopped.name
  target_id = "alerts"
  arn       = var.alert_topic_arn

  input_transformer {
    input_paths = {
      machine = "$.detail.stateMachineArn"
      status  = "$.detail.status"
      exec    = "$.detail.executionArn"
    }
    input_template = "\"${var.environment}: domain workflow <status>. <machine> stopped without finishing: <exec>. Check the order on the customer's Domains tab and press Retry.\""
  }
}

resource "aws_cloudwatch_metric_alarm" "domains" {
  for_each = var.environment == "prod" ? local.domain_metrics : {}

  alarm_name          = "${local.prefix}domains-${each.key}"
  alarm_description   = each.value
  namespace           = "Booqy/Domains"
  metric_name         = each.key
  statistic           = "Maximum"
  period              = 86400
  evaluation_periods  = 1
  threshold           = 1
  comparison_operator = "GreaterThanOrEqualToThreshold"
  treat_missing_data  = "notBreaching"
  alarm_actions       = [var.alert_topic_arn]
  ok_actions          = [var.alert_topic_arn]

  tags = {
    Environment = var.environment
  }
}
