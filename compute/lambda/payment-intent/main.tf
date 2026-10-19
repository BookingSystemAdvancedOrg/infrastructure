locals {
  function_name = var.environment == "prod" ? "payment-intent" : "${var.environment}-payment-intent"
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
    variables = {
      # Trust the viewer IP from the admin app's CloudFront (/api/*) for the
      # per-IP limits and signing evidence (shared/http.py source_ip).
      CLOUDFRONT_EDGE_SECRET          = var.cloudfront_edge_secret
      TENANT_TABLE_NAME               = var.tenant_table_name
      LOCATION_TABLE_NAME             = var.location_table_name
      LOCATION_ID_INDEX_NAME          = var.location_id_index_name
      ENVIRONMENT                     = var.environment
      ORDER_TABLE_NAME                = var.order_table_name
      STRIPE_SECRET_ARN               = var.stripe_secret_arn # platform Stripe key secret (Connect) - creates the Checkout Session on the tenant's connected account
      STRIPE_API_VERSION              = var.stripe_api_version
      MENU_TABLE_NAME                 = var.menu_table_name
      CUSTOMER_SITE_URL               = var.customer_site_url
      RESERVATION_LINK_KEY_SECRET_ARN = var.reservation_link_key_secret_arn # status token in the answer
      TURNSTILE_REQUIRED              = var.turnstile_required ? "true" : "false"
      TURNSTILE_SECRET_ARN            = var.turnstile_secret_arn
      REQUEST_GUARD_TABLE_NAME        = var.request_guard_table_name
    }
  }

  tags = {
    Environment = var.environment
  }
}
