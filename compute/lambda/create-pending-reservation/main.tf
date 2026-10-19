locals {
  function_name = var.environment == "prod" ? "create-pending-reservation" : "${var.environment}-create-pending-reservation"
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
      CLOUDFRONT_EDGE_SECRET               = var.cloudfront_edge_secret
      TENANT_TABLE_NAME                    = var.tenant_table_name
      LOCATION_ID_INDEX_NAME               = var.location_id_index_name
      ENVIRONMENT                          = var.environment
      LOCATION_TABLE_NAME                  = var.location_table_name
      PUBLISHED_LAYOUT_SNAPSHOT_TABLE_NAME = var.published_layout_snapshot_table_name
      SLOT_OCCUPANCY_TABLE_NAME            = var.slot_occupancy_table_name
      RESERVATION_TABLE_NAME               = var.reservation_table_name
      USER_TABLE_NAME                      = var.user_table_name
      PAYMENT_DELINQUENCY_TABLE_NAME       = var.payment_delinquency_table_name
      RESERVATION_LINK_KEY_SECRET_ARN      = var.reservation_link_key_secret_arn # signs the manage token returned to the guest
      STRIPE_SECRET_ARN                    = var.stripe_secret_arn               # platform Stripe key secret (Connect) - to create a SetupIntent (card-on-file, no charge yet) on the tenant's connected account
      STRIPE_API_VERSION                   = var.stripe_api_version
      TURNSTILE_REQUIRED                   = var.turnstile_required ? "true" : "false" # bot check on online bookings (the sites show the widget)
      TURNSTILE_SECRET_ARN                 = var.turnstile_secret_arn                  # platform Turnstile secret key {"secretKey": "..."}
      REQUEST_GUARD_TABLE_NAME             = var.request_guard_table_name              # attempt limits per IP / phone / e-mail
    }
  }

  tags = {
    Environment = var.environment
  }
}
