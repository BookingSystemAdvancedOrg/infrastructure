# Customer-facing catering API (NONE auth at the gateway - the magic-link
# HMAC in the x-order-token header is the authentication boundary).
#
# SIGNING_WEBHOOK_URL is passed to the signing provider per signing order,
# so the provider calls back to catering-signing-webhook.

locals {
  function_name = var.environment == "prod" ? "catering-customer" : "${var.environment}-catering-customer"
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
      TENANT_TABLE_NAME                   = var.tenant_table_name
      LOCATION_ID_INDEX_NAME              = var.location_id_index_name
      ENVIRONMENT                         = var.environment
      CATERING_REQUESTS_TABLE_NAME        = var.catering_requests_table_name
      CATERING_REQUEST_HISTORY_TABLE_NAME = var.catering_request_history_table_name
      LOCATION_TABLE_NAME                 = var.location_table_name
      CATERING_DOCUMENTS_BUCKET_NAME      = var.catering_documents_bucket_name
      LINK_SIGNING_KEY_SECRET_ARN         = var.link_signing_key_secret_arn
      SIGNING_PROVIDER_SECRET_ARN         = var.signing_provider_secret_arn
      STRIPE_SECRET_ARN                   = var.stripe_secret_arn
      STRIPE_API_VERSION                  = var.stripe_api_version
      CUSTOMER_SITE_URL                   = var.customer_site_url
      SIGNING_WEBHOOK_URL                 = var.signing_webhook_url
    }
  }

  tags = {
    Environment = var.environment
  }

  depends_on = [aws_cloudwatch_log_group.this]
}
