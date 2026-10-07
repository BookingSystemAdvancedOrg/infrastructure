
locals {
  function_name = var.environment == "prod" ? "catering-requests" : "${var.environment}-catering-requests"
}

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
      LOCATION_TABLE_NAME                 = var.location_table_name
      CATERING_DISCOUNT_TIERS_TABLE_NAME  = var.catering_discount_tiers_table_name
      MENU_TABLE_NAME                     = var.menu_table_name
      CATERING_REQUEST_HISTORY_TABLE_NAME = var.catering_request_history_table_name
      TURNSTILE_SECRET_ARN                = var.turnstile_secret_arn
      LINK_SIGNING_KEY_SECRET_ARN         = var.link_signing_key_secret_arn
      CUSTOMER_SITE_URL                   = var.customer_site_url
    }
  }

  tags = {
    Environment = var.environment
  }

  depends_on = [aws_cloudwatch_log_group.this]
}
