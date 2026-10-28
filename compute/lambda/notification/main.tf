locals {
  function_name = var.environment == "prod" ? "notification" : "${var.environment}-notification"
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

  timeout     = 28
  memory_size = 512

  environment {
    variables = merge({
      TENANT_TABLE_NAME                    = var.tenant_table_name
      LOCATION_TABLE_NAME                  = var.location_table_name
      LOCATION_ID_INDEX_NAME               = var.location_id_index_name
      ENVIRONMENT                          = var.environment
      NO_REPLY_EMAIL_ADDRESS               = var.no_reply_email_address
      ADMIN_DASHBOARD_URL                  = var.admin_dashboard_url
      CUSTOMER_SITE_URL                    = var.customer_site_url # base of the catering magic links in customer emails
      SITE_DOMAIN                          = var.site_domain
      CATERING_LINK_SIGNING_KEY_SECRET_ARN = var.catering_link_signing_key_secret_arn
      RESERVATION_LINK_KEY_SECRET_ARN      = var.reservation_link_key_secret_arn # rebuilds the guest's manage link for emails/SMS
      RESERVATION_TABLE_NAME               = var.reservation_table_name          # routes this table's stream records
      ORDER_TABLE_NAME                     = var.order_table_name                # routes this table's stream records
      CATERING_REQUESTS_TABLE_NAME         = var.catering_requests_table_name    # routes this table's stream records
      MAIL_OUTBOX_BUCKET_NAME              = var.mail_outbox_bucket_name         # dev only: save emails here instead of SES ("" = send)
      FINANCE_TABLE_NAME                   = var.finance_table_name              # counts emails and SMS sent per restaurant and day
      # + the consent withdrawal link in booking confirmations (root privacy-consent.tf)
    }, var.privacy_env)
  }

  tags = {
    Environment = var.environment
  }
}
