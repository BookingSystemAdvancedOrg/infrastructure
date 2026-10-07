# Public site bootstrap (/site-config?host=<hostname>, NONE auth). Returns only
# public fields, never Stripe ids, owner contact details or plan internals,
# and answers 404 for hosts that aren't an active domain of an active tenant.

locals {
  function_name = var.environment == "prod" ? "tenant-site-config" : "${var.environment}-tenant-site-config"
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

  timeout     = 10
  memory_size = 256

  environment {
    variables = {
      LOCATION_ID_INDEX_NAME = var.location_id_index_name
      ENVIRONMENT            = var.environment
      TENANT_TABLE_NAME      = var.tenant_table_name
      LOCATION_TABLE_NAME    = var.location_table_name
      TURNSTILE_SITE_KEY     = var.turnstile_site_key
      STRIPE_PUBLISHABLE_KEY = var.stripe_publishable_key
    }
  }

  tags = {
    Environment = var.environment
  }

  depends_on = [aws_cloudwatch_log_group.this]
}
