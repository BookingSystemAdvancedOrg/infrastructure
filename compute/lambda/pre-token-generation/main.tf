# Cognito pre token generation trigger for the tenant user pool - adds
# tenant_id and role claims to every ID and access token (see src/handler.py).
#
# Deployed as a zip straight from this repo, unlike the application Lambdas
# (container images pushed by the backend repo): this trigger runs on every
# sign-in and refresh, so it must never be a placeholder. The code is a few
# lines with no dependencies; tests live in tests/ and run in CI.

terraform {
  required_providers {
    archive = {
      source = "hashicorp/archive"
    }
  }
}

locals {
  function_name = var.environment == "prod" ? "pre-token-generation" : "${var.environment}-pre-token-generation"
}

data "archive_file" "this" {
  type        = "zip"
  source_file = "${path.module}/src/handler.py"
  output_path = "${path.module}/.build/pre-token-generation.zip"
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

  tags = {
    Environment = var.environment
  }

  depends_on = [aws_cloudwatch_log_group.this]
}
