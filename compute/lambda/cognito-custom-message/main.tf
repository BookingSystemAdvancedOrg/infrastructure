# Cognito custom message trigger: the "forgot password" email as a link to
# the app's reset page (see src/handler.py). One instance per user pool
# (config.tf) - the tenant pool's links go to the restaurant admin app in
# Swedish, the operator pool's to SBS Admin in English.
#
# Deployed as a zip straight from this repo, like pre-token-generation: the
# trigger runs inside Cognito's ForgotPassword call, so a placeholder image
# would break every password reset. No dependencies; tests in tests/ run in
# CI before Terraform.

terraform {
  required_providers {
    archive = {
      source = "hashicorp/archive"
    }
  }
}

locals {
  function_name = var.environment == "prod" ? var.name : "${var.environment}-${var.name}"
}

data "archive_file" "this" {
  type        = "zip"
  source_file = "${path.module}/src/handler.py"
  output_path = "${path.module}/.build/${local.function_name}.zip"
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
  # Every code/config change Terraform makes is published as a new version;
  # Cognito invokes the "live" alias (alias.tf).
  publish = true

  function_name    = local.function_name
  role             = var.role_arn
  runtime          = "python3.13"
  handler          = "handler.handler"
  architectures    = ["arm64"]
  filename         = data.archive_file.this.output_path
  source_code_hash = data.archive_file.this.output_base64sha256

  # Cognito gives a trigger 5 seconds in total; this one does no I/O.
  timeout     = 3
  memory_size = 128

  environment {
    variables = {
      RESET_URL = var.reset_url
      LANGUAGE  = var.language
    }
  }

  tags = {
    Environment = var.environment
  }

  depends_on = [aws_cloudwatch_log_group.this]
}
