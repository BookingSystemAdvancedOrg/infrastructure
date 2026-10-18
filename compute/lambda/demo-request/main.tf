# "Boka en demo" on the public site (booqy-website, /demo): the form posts to
# https://<platform domain>/api/demo-request, the landing distribution
# forwards it here (network/platform-domain, OAC-signed), and this function
# emails the request to sales with Reply-To set to the person who asked
# (see src/handler.py).
#
# Deployed as a zip straight from this repo, like pre-token-generation: a
# few lines with no dependencies, nothing for the backend repo to own. Tests
# in tests/ run in CI before Terraform.

terraform {
  required_providers {
    archive = {
      source = "hashicorp/archive"
    }
  }
}

locals {
  function_name = var.environment == "prod" ? "demo-request" : "${var.environment}-demo-request"
}

data "archive_file" "this" {
  type        = "zip"
  source_file = "${path.module}/src/handler.py"
  output_path = "${path.module}/.build/demo-request.zip"
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
  publish = true

  function_name    = local.function_name
  role             = var.role_arn
  runtime          = "python3.13"
  handler          = "handler.handler"
  architectures    = ["arm64"]
  filename         = data.archive_file.this.output_path
  source_code_hash = data.archive_file.this.output_base64sha256

  # One SES call.
  timeout     = 10
  memory_size = 128

  environment {
    variables = {
      DEMO_RECIPIENT = var.recipient
      FROM_ADDRESS   = var.from_address
      ENVIRONMENT    = var.environment
    }
  }

  tags = {
    Environment = var.environment
  }

  depends_on = [aws_cloudwatch_log_group.this]
}

# Stable entry point, follows each version Terraform publishes (zip from this
# repo - no CodeDeploy traffic shifting).
resource "aws_lambda_alias" "live" {
  name             = "live"
  function_name    = aws_lambda_function.this.function_name
  function_version = aws_lambda_function.this.version
}

# AWS_IAM: only the landing CloudFront distribution may call it (OAC signs
# every request; the invoke permission in config.tf names that distribution).
# Calling the bare URL from the internet gets 403.
resource "aws_lambda_function_url" "this" {
  function_name      = aws_lambda_function.this.function_name
  qualifier          = aws_lambda_alias.live.name
  authorization_type = "AWS_IAM"
}
