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
  architectures = ["arm64"]

  timeout     = 28
  memory_size = 512

  environment {
    variables = {
      TENANT_TABLE_NAME                    = var.tenant_table_name
      LOCATION_TABLE_NAME                  = var.location_table_name
      LOCATION_ID_INDEX_NAME               = var.location_id_index_name
      ENVIRONMENT                          = var.environment
      NO_REPLY_EMAIL_ADDRESS               = var.no_reply_email_address
      ADMIN_DASHBOARD_URL                  = var.admin_dashboard_url
      CUSTOMER_SITE_URL                    = var.customer_site_url # base of the catering magic links in customer emails
      CATERING_LINK_SIGNING_KEY_SECRET_ARN = var.catering_link_signing_key_secret_arn
      RESERVATION_LINK_KEY_SECRET_ARN      = var.reservation_link_key_secret_arn # rebuilds the guest's manage link for emails/SMS
      RESERVATION_TABLE_NAME               = var.reservation_table_name          # routes this table's stream records
    }
  }

  tags = {
    Environment = var.environment
  }
}
