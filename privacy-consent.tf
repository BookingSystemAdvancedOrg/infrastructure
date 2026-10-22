# Guest privacy: the marketing consent log, the data-retention job and the
# owner's privacy API (application shared/consent.py, shared/retention.py,
# functions/data-retention, functions/guest-privacy; docs/privacy.md).
#
# Kept in its own file. What had to go into shared files (config.tf: the two
# *_ecr modules, the release map, a few env inputs; outputs.tf: the ECR map)
# is there because CI derives its bootstrap -target list from config.tf.

locals {
  retention_env = {
    RETENTION_BOOKING_DAYS         = tostring(var.data_retention.booking_days)
    RETENTION_GUEST_MONTHS         = tostring(var.data_retention.guest_months)
    RETENTION_CANCELLED_MONTHS     = tostring(var.data_retention.cancelled_months)
    RETENTION_ACCOUNTING_YEARS     = tostring(var.data_retention.accounting_years)
    RETENTION_SUPPRESSION_MONTHS   = tostring(var.data_retention.suppression_months)
    RETENTION_CONSENT_HISTORY_DAYS = tostring(var.data_retention.consent_history_days)
  }
  # Extra environment for existing functions (their modules merge it in).
  privacy_env_booking = {
    CONSENT_TABLE_NAME         = module.consent_log.table_name
    RESERVATION_RETENTION_DAYS = tostring(var.data_retention.booking_days)
  }
  privacy_env_consent = { CONSENT_TABLE_NAME = module.consent_log.table_name }
  privacy_env_purge = {
    CONSENT_TABLE_NAME        = module.consent_log.table_name
    CONSENT_TENANT_INDEX_NAME = module.consent_log.tenant_index_name
  }
  privacy_env_mark_arrived = { RESERVATION_RETENTION_DAYS = tostring(var.data_retention.booking_days) }
  # Booking confirmations sign the guest's withdrawal link (shared/messages.py).
  privacy_env_notification = {
    MARKETING_LINK_BASE           = "${local.admin_app_url}/api"
    MARKETING_LINK_KEY_SECRET_ARN = module.marketing.link_key_secret_arn
    SES_CONFIGURATION_SET         = aws_sesv2_configuration_set.transactional.configuration_set_name
  }
}

module "consent_log" {
  source      = "./storage/dynamodb/consent-log"
  environment = var.env
}

# --- data-retention: nightly, dry run until var.data_retention_dry_run = false
module "data_retention_role" {
  source             = "./security/iam/data-retention"
  environment        = var.env
  region             = var.aws_region
  tenant_table_arn   = module.tenant.table_arn
  location_table_arn = module.location.table_arn
  guest_table_arns = [
    module.reservation.table_arn,
    module.order.table_arn,
    module.catering_requests.table_arn,
    module.catering_request_history.table_arn,
  ]
  consent_table_arn   = module.consent_log.table_arn
  marketing_table_arn = module.marketing.table_arn
  alert_topic_arn     = module.alerts.topic_arn
}

module "data_retention_fn" {
  source                              = "./compute/lambda/data-retention"
  environment                         = var.env
  role_arn                            = module.data_retention_role.role_arn
  ecr_repository_url                  = module.data_retention_ecr.data_retention_ecr_repository_url
  scheduler_invoke_role_arn           = module.data_retention_role.scheduler_role_arn
  schedule_expression                 = var.data_retention_schedule
  dry_run                             = var.data_retention_dry_run
  retention_env                       = local.retention_env
  tenant_table_name                   = module.tenant.table_name
  location_table_name                 = module.location.table_name
  reservation_table_name              = module.reservation.table_name
  order_table_name                    = module.order.table_name
  catering_requests_table_name        = module.catering_requests.table_name
  catering_request_history_table_name = module.catering_request_history.table_name
  consent_table_name                  = module.consent_log.table_name
  consent_tenant_index_name           = module.consent_log.tenant_index_name
  marketing_table_name                = module.marketing.table_name
  alert_topic_arn                     = module.alerts.topic_arn
}

# --- guest-privacy: owner API (/privacy/*)
module "guest_privacy_role" {
  source              = "./security/iam/guest-privacy"
  environment         = var.env
  region              = var.aws_region
  tenant_table_arn    = module.tenant.table_arn
  consent_table_arn   = module.consent_log.table_arn
  marketing_table_arn = module.marketing.table_arn
  location_table_arn  = module.location.table_arn
  guest_table_arns = [
    module.reservation.table_arn,
    module.order.table_arn,
    module.catering_requests.table_arn,
  ]
}

# The shared tenant-context read policy (the tenant check in for_jwt).
resource "aws_iam_role_policy_attachment" "guest_privacy_tenant_context" {
  role       = module.guest_privacy_role.role_name
  policy_arn = module.tenant_context_policy.policy_arn
}

module "guest_privacy_fn" {
  source                 = "./compute/lambda/guest-privacy"
  environment            = var.env
  role_arn               = module.guest_privacy_role.role_arn
  ecr_repository_url     = module.guest_privacy_ecr.guest_privacy_ecr_repository_url
  retention_env          = local.retention_env
  tenant_table_name      = module.tenant.table_name
  location_table_name    = module.location.table_name
  location_id_index_name = module.location.location_id_index_name
  user_table_name        = module.user.table_name
  consent_table_name     = module.consent_log.table_name
  marketing_table_name   = module.marketing.table_name

  reservation_table_name       = module.reservation.table_name
  order_table_name             = module.order.table_name
  catering_requests_table_name = module.catering_requests.table_name
}

# --- consent log access for existing functions --------------------------------
# Append-only writers get Query + PutItem only (no UpdateItem, no DeleteItem),
# so no guest-facing function can rewrite or remove a consent record.
resource "aws_iam_role_policy" "consent_log_append" {
  for_each = {
    create_pending_reservation = module.create_pending_reservation_role.role_name
    payment_intent             = module.payment_intent_role.role_name
    catering_requests          = module.catering_requests_role.role_name
    marketing_public           = module.marketing.role_names["marketing-public"]
    marketing_sync             = module.marketing.role_names["marketing-sync"]
  }
  name = "consent-log-append"
  role = each.value

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Sid      = "AppendConsentRecords"
      Effect   = "Allow"
      Action   = ["dynamodb:Query", "dynamodb:PutItem"]
      Resource = module.consent_log.table_arn
    }]
  })
}

# marketing-send only reads: the latest consent before every email.
resource "aws_iam_role_policy" "consent_log_read_send" {
  name = "consent-log-read"
  role = module.marketing.role_names["marketing-send"]

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Sid      = "CheckConsentBeforeSending"
      Effect   = "Allow"
      Action   = "dynamodb:Query"
      Resource = module.consent_log.table_arn
    }]
  })
}

# notification reads the marketing link key (read only, this one secret) to
# sign the withdrawal link in booking confirmations. Default Secrets Manager
# KMS key, so no kms:Decrypt grant is needed.
resource "aws_iam_role_policy" "notification_withdraw_link" {
  name = "marketing-link-key-read"
  role = module.notification_role.role_name

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Sid      = "SignWithdrawalLinks"
      Effect   = "Allow"
      Action   = "secretsmanager:GetSecretValue"
      Resource = module.marketing.link_key_secret_arn
    }]
  })
}

# tenant-purge deletes an offboarded restaurant's records (found by index).
resource "aws_iam_role_policy" "consent_log_purge" {
  name = "consent-log-purge"
  role = module.tenant_purge_role.role_name

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Sid      = "PurgeTenantConsentRecords"
      Effect   = "Allow"
      Action   = ["dynamodb:Query", "dynamodb:DeleteItem", "dynamodb:BatchWriteItem"]
      Resource = [module.consent_log.table_arn, "${module.consent_log.table_arn}/index/byTenant"]
    }]
  })
}
