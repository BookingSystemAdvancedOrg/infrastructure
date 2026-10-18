locals {
  function_name = var.environment == "prod" ? "manage-auth" : "${var.environment}-manage-auth"
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
      ENVIRONMENT           = var.environment
      COGNITO_USER_POOL_ID  = var.cognito_user_pool_id
      COGNITO_CLIENT_ID     = var.cognito_client_id
      COGNITO_CLIENT_SECRET = var.cognito_client_secret
      # per-IP limits on forgot/reset password (shared/request_guard.py)
      REQUEST_GUARD_TABLE_NAME = var.request_guard_table_name
    }
  }

  tags = {
    Environment = var.environment
  }
}
