# Operator-facing platform API (/platform/* - operator user pool JWT with
# the platform/admin scope, see network/api-gateway). The code lives in the
# Booqy Console repo (api/), whose pipeline pushes the image and updates this
# function - not in the backend application repo.
#
# Creating a tenant = one TransactWriteItems (PROFILE + SLUG# uniqueness row,
# status "provisioning") + StartExecution of the onboarding workflow. Every
# other provisioning step happens in the workflow, never in this Lambda.

locals {
  function_name = var.environment == "prod" ? "platform-tenants" : "${var.environment}-platform-tenants"
}

# Declared explicitly, not left to be auto-created on first invoke, so log
# retention is actually controlled instead of defaulting to "never expire".
resource "aws_cloudwatch_log_group" "this" {
  name              = "/aws/lambda/${local.function_name}"
  retention_in_days = 30

  tags = {
    Environment = var.environment
  }
}

resource "aws_lambda_function" "this" {
  # Every code/config change Terraform makes is published as a new version.
  # Callers never invoke the function directly - they invoke the "live"
  # alias (alias.tf).
  publish = true

  function_name = local.function_name
  role          = var.role_arn
  package_type  = "Image"
  image_uri     = "${var.ecr_repository_url}:latest"
  # Terraform only sets the first image. The app pipelines own the code and
  # release <repo>:<sha>; without this every apply after an app release
  # resets image_uri to :latest, publishes a new version of every function
  # and the release step has to roll all of them out again.
  lifecycle {
    ignore_changes = [image_uri]
  }
  architectures = ["arm64"]

  # API calls are cut by API Gateway at 29 s regardless; the longer timeout
  # is for the scheduled tasks: the invoicing run makes about five Stripe
  # calls per restaurant (some 2 s), so 300 s covers well over 100
  # restaurants. It stops starting restaurants 30 s before the end and the
  # next daily run takes the rest.
  timeout     = 300
  memory_size = 512

  environment {
    variables = {
      ENVIRONMENT                     = var.environment
      TENANT_TABLE_NAME               = var.tenant_table_name
      LOCATION_TABLE_NAME             = var.location_table_name
      LOCATION_ID_INDEX_NAME          = var.location_id_index_name
      USER_TABLE_NAME                 = var.user_table_name
      USER_TENANT_INDEX_NAME          = var.user_tenant_index_name
      TENANT_USER_POOL_ID             = var.tenant_user_pool_id
      OWNER_GROUP_NAME                = var.owner_group_name
      ONBOARDING_STATE_MACHINE_ARN    = var.onboarding_state_machine_arn
      DOMAIN_ATTACH_STATE_MACHINE_ARN = var.domain_attach_state_machine_arn
      DOMAIN_DETACH_STATE_MACHINE_ARN = var.domain_detach_state_machine_arn
      OFFBOARDING_STATE_MACHINE_ARN   = var.offboarding_state_machine_arn
      STRIPE_SECRET_ARN               = var.stripe_secret_arn
      STRIPE_API_VERSION              = var.stripe_api_version
      PLATFORM_DOMAIN                 = var.platform_domain
      TENANT_DOMAIN_CNAME_TARGET      = var.tenant_domain_cname_target
      ADMIN_APP_URL                   = var.admin_app_url
      PLATFORM_ADMIN_APP_URL          = var.platform_admin_app_url
      OPERATOR_USER_POOL_ID           = var.operator_user_pool_id
      OPERATOR_GROUP_NAME             = var.operator_group_name
      OPERATOR_OWNER_GROUP_NAME       = var.operator_owner_group_name # owners: may change any operator's e-mail
      MAIL_OUTBOX_BUCKET_NAME         = var.mail_outbox_bucket_name   # dev only: GET /platform/outbox reads it, news is saved there ("" = off)
      # News to the restaurant owners (Mail page): From and default Reply-To
      NO_REPLY_EMAIL_ADDRESS = var.no_reply_email_address
      SUPPORT_EMAIL_ADDRESS  = var.support_email_address
      # Restaurant domains bought / connected from Booqy Console
      DOMAIN_PROVISION_STATE_MACHINE_ARN = var.domain_provision_state_machine_arn
      DOMAIN_DOCUMENTS_BUCKET            = var.domain_documents_bucket_name
      # Own domains: the 301s from the slug address and www to the live own
      # domain ("" = not written), and the dev console's simulated buy,
      # transfer and connect (never in prod).
      SITE_REDIRECT_KVS_ARN = var.site_redirect_kvs_arn
      DOMAINS_SIMULATE      = var.environment == "prod" ? "false" : "true"
      # Each operator's background image library (/platform/me/backdrops)
      USER_BACKDROPS_BUCKET     = var.user_backdrops_bucket_name
      USER_BACKDROPS_TABLE_NAME = var.user_backdrops_table_name
      # Website page: booqy.se's cookieless statistics (site-analytics/)
      SITE_ANALYTICS_TABLE_NAME = var.site_analytics_table_name
      # Finance: subscriptions (Stripe Billing), the Finance page, dunning
      FINANCE_TABLE_NAME          = var.finance_table_name
      FINANCE_ROLLUP_FUNCTION_ARN = var.finance_rollup_alias_arn
      # Locations tab: each location's printers (status, add, rename, test
      # print, remove) and the CloudPRNT server URL a new printer is given
      PRINT_TABLE_NAME = var.print_table_name
      PRINT_SERVER_URL = var.print_server_url
      # Website tab: the restaurant's site repo (site-repo function)
      SITE_REPO_FUNCTION_ARN = var.site_repo_function_arn
      # Users tab: every sign-in account of a customer, with the admin's own
      # rules (manage-user, tenant-account staffAccess), shared/console_invoke.py
      MANAGE_USER_FUNCTION_ARN    = var.manage_user_function_arn
      TENANT_ACCOUNT_FUNCTION_ARN = var.tenant_account_function_arn
      SITE_REPOS_ENABLED          = var.site_repos_enabled ? "true" : "false"
      # Dev: test customers (dev console) and their sandbox hosts; "" = off
      TEST_SITES_ENABLED         = var.test_main_domain != "" ? "true" : "false"
      TEST_MAIN_DOMAIN           = var.test_main_domain
      TEST_DEV_DOMAIN            = var.test_dev_domain
      ALERT_TOPIC_ARN            = var.alert_topic_arn
      BILLING_TAX_RATE_ID        = var.billing_tax_rate_id
      BILLING_DAYS_UNTIL_DUE     = tostring(var.billing_days_until_due)
      BILLING_SUSPEND_AFTER_DAYS = tostring(var.billing_suspend_after_days)
      # In advance on the 1st: no card yet = emailed, due in this many days
      BILLING_DAYS_UNTIL_DUE_NO_CARD = tostring(var.billing_days_until_due_no_card)
      # Booqy's details on every invoice (mervärdesskattelagen 17 kap 24 §), not secret
      BILLING_SELLER_JSON = jsonencode(var.billing_seller)
      # Reminders (restaurant and operators), fees and interest (dunning task)
      BILLING_REMINDER_STEPS      = join(",", [for d in var.billing_reminder_steps : tostring(d)])
      BILLING_FINAL_NOTICE_DAYS   = tostring(var.billing_final_notice_days)
      BILLING_REMINDER_FEE_SEK    = tostring(var.billing_reminder_fee_sek)
      BILLING_LATE_FEE_SEK        = tostring(var.billing_late_fee_sek)
      BILLING_LATE_FEE_AFTER_DAYS = tostring(var.billing_late_fee_after_days)
      BILLING_REFERENCE_RATE_PCT  = tostring(var.billing_reference_rate_pct)
      BILLING_INTEREST_MARGIN_PCT = tostring(var.billing_interest_margin_pct)
      # Terms: try-out (leave at the end of any month, becomes a subscription
      # after BILLING_TRIAL_MONTHS) or subscription (BILLING_NOTICE_MONTHS notice)
      BILLING_NOTICE_MONTHS = tostring(var.billing_notice_months)
      BILLING_TRIAL_MONTHS  = tostring(var.billing_trial_months)
      # Dev twins (dev only, docs/DEV-TWINS.md); "" = off
      DEV_TWIN_FUNCTION_PREFIX   = var.environment == "prod" ? "" : var.dev_twin_function_prefix
      DEV_TWIN_OWNER_EMAIL       = var.environment == "prod" ? "" : var.dev_twin_owner_email
      DEV_TWIN_STRIPE_ACCOUNT_ID = var.environment == "prod" ? "" : var.dev_twin_stripe_account_id
    }
  }

  tags = {
    Environment = var.environment
  }

  depends_on = [aws_cloudwatch_log_group.this]
}

# No Lambda retries of async invokes (the scheduled tasks, the newsletter
# send): the daily tasks catch up on their next run and the newsletter
# saves progress per recipient; failures raise the errors alarm below.
resource "aws_lambda_function_event_invoke_config" "live" {
  function_name                = aws_lambda_function.this.function_name
  qualifier                    = aws_lambda_alias.live.name
  maximum_retry_attempts       = 0
  maximum_event_age_in_seconds = 3600
}

# Dunning: once a day the function checks every customer's subscription
# (PROFILE.billing, kept current by platform-stripe-webhook) and suspends
# those past due longer than BILLING_SUSPEND_AFTER_DAYS, resumes the ones
# it suspended that have paid since, and emails the operators. It also runs
# the Free plan: the owner's email 14 days before a free period ends (SES,
# the same no-reply sender as the console's news) and, the day after the
# last free day, the move to the plan chosen for afterwards. The same
# code path as Suspend / Resume in Booqy Console; the event carries no
# routeKey, so API Gateway's JWT check does not apply and only the
# scheduler role may invoke it this way.
resource "aws_scheduler_schedule" "dunning" {
  name                = "${local.function_name}-dunning"
  group_name          = "default"
  schedule_expression = var.dunning_schedule_expression

  flexible_time_window {
    mode = "OFF"
  }

  target {
    arn      = aws_lambda_alias.live.arn
    role_arn = var.scheduler_invoke_role_arn
    input    = jsonencode({ financeTask = "dunning" })

    retry_policy {
      maximum_retry_attempts       = 2
      maximum_event_age_in_seconds = 3600
    }
  }
}

# Own domains, daily (prod): expiry and renewals of the domains registered
# through Booqy, failed Route 53 Domains operations, auto-renew left off and
# unconfirmed registrant e-mails, as Booqy/Domains metrics (the alarms are
# in orchestration/tenant-workflows/domain-alarms.tf); expiry and auto-renew
# are also written to each order row for the Domains tab.
resource "aws_scheduler_schedule" "domain_health" {
  count = var.environment == "prod" ? 1 : 0

  name                         = "${local.function_name}-domain-health"
  group_name                   = "default"
  schedule_expression          = "cron(15 6 * * ? *)"
  schedule_expression_timezone = "Europe/Stockholm"

  flexible_time_window {
    mode = "OFF"
  }

  target {
    arn      = aws_lambda_alias.live.arn
    role_arn = var.scheduler_invoke_role_arn
    input    = jsonencode({ domainTask = "health" })

    retry_policy {
      maximum_retry_attempts       = 2
      maximum_event_age_in_seconds = 3600
    }
  }
}

# Invoicing: on the 1st the function builds one Stripe invoice per
# restaurant for that calendar month, in advance (the monthly price; the
# first month pro rata from the start day; SMS are included and the Free
# plan has no charge), and Stripe charges the saved card or emails it. It
# runs every day: on a start day (or the first paid day after Free) it
# invoices the rest of that month, on other days only what a failed or
# unfinished run left, so a Stripe outage on the 1st is caught up the
# next morning. Idempotent per restaurant and period
# (the ledger, PROFILE.billing and a look-up in Stripe before anything is
# created); "Run invoicing" in Booqy Console does the same by hand.
resource "aws_scheduler_schedule" "invoicing" {
  name                = "${local.function_name}-invoicing"
  group_name          = "default"
  schedule_expression = var.invoicing_schedule_expression

  flexible_time_window {
    mode = "OFF"
  }

  target {
    arn      = aws_lambda_alias.live.arn
    role_arn = var.scheduler_invoke_role_arn
    input    = jsonencode({ financeTask = "invoice" })

    retry_policy {
      maximum_retry_attempts       = 2
      maximum_event_age_in_seconds = 3600
    }
  }
}

# Any failed invocation (an exception or a timeout) of the scheduled tasks
# above: the invoicing and dunning runs email their own summary when they
# finish, so this catches the runs that never got that far. API requests
# answer errors themselves and do not count here.
resource "aws_cloudwatch_metric_alarm" "errors" {
  alarm_name          = "${local.function_name}-errors"
  alarm_description   = "platform-tenants failed (invoicing, dunning or an API request crashed or timed out). Check its logs; a missed invoicing run is caught up by the next daily run or Run invoicing in Booqy Console."
  namespace           = "AWS/Lambda"
  metric_name         = "Errors"
  dimensions          = { FunctionName = aws_lambda_function.this.function_name }
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
