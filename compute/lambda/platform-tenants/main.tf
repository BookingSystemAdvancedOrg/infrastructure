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
  # is for the scheduled dunning task and the Stripe invoice import.
  timeout     = 60
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
      MAIL_OUTBOX_BUCKET_NAME         = var.mail_outbox_bucket_name # dev only: GET /platform/outbox reads it, news is saved there ("" = off)
      # News to the restaurant owners (Mail page): From and default Reply-To
      NO_REPLY_EMAIL_ADDRESS = var.no_reply_email_address
      SUPPORT_EMAIL_ADDRESS  = var.support_email_address
      # Restaurant domains bought / connected from Booqy Console
      DOMAIN_PROVISION_STATE_MACHINE_ARN = var.domain_provision_state_machine_arn
      DOMAIN_DOCUMENTS_BUCKET            = var.domain_documents_bucket_name
      # Finance: subscriptions (Stripe Billing), the Finance page, dunning
      FINANCE_TABLE_NAME          = var.finance_table_name
      FINANCE_ROLLUP_FUNCTION_ARN = var.finance_rollup_alias_arn
      ALERT_TOPIC_ARN             = var.alert_topic_arn
      BILLING_TAX_RATE_ID         = var.billing_tax_rate_id
      BILLING_DAYS_UNTIL_DUE      = tostring(var.billing_days_until_due)
      BILLING_SUSPEND_AFTER_DAYS  = tostring(var.billing_suspend_after_days)
      # Reminders, late fee and interest on unpaid invoices (dunning task)
      BILLING_REMINDER_INTERVAL_DAYS = tostring(var.billing_reminder_interval_days)
      BILLING_LATE_FEE_SEK           = tostring(var.billing_late_fee_sek)
      BILLING_LATE_FEE_AFTER_DAYS    = tostring(var.billing_late_fee_after_days)
      BILLING_REFERENCE_RATE_PCT     = tostring(var.billing_reference_rate_pct)
      BILLING_INTEREST_MARGIN_PCT    = tostring(var.billing_interest_margin_pct)
      # Terms: try-out (leave at the end of any month, becomes a subscription
      # after BILLING_TRIAL_MONTHS) or subscription (BILLING_NOTICE_MONTHS notice)
      BILLING_NOTICE_MONTHS = tostring(var.billing_notice_months)
      BILLING_TRIAL_MONTHS  = tostring(var.billing_trial_months)
      # Invoiced in arrears on the 25th for the period 25th to 24th; SMS per part
      BILLING_SMS_PRICE_SEK = tostring(var.sms_price_sek)
    }
  }

  tags = {
    Environment = var.environment
  }

  depends_on = [aws_cloudwatch_log_group.this]
}

# Dunning: once a day the function checks every customer's subscription
# (PROFILE.billing, kept current by platform-stripe-webhook) and suspends
# those past due longer than BILLING_SUSPEND_AFTER_DAYS, resumes the ones
# it suspended that have paid since, and emails the operators. The same
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

# Invoicing: on the 25th, after the period from the 25th to the 24th has
# ended, the function builds one Stripe invoice per restaurant for that
# period (the monthly price pro rata by days, plus the SMS parts sent at
# the restaurant's SMS price) and Stripe emails or charges it. Idempotent
# per restaurant and period; a missed run is caught up by the next one or
# by "Run invoicing" in Booqy Console.
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
