# Owner API for guest privacy (application functions/guest-privacy): the
# restaurant's privacy notice (GET/PUT/DELETE /privacy/notice) and the
# consent lookup / withdrawal on a guest's behalf (/privacy/consents).
# Tenant pool JWT, owners only (checked in the handler).

locals {
  function_name = var.environment == "prod" ? "guest-privacy" : "${var.environment}-guest-privacy"
}

resource "aws_cloudwatch_log_group" "this" {
  name              = "/aws/lambda/${local.function_name}"
  retention_in_days = 30

  tags = {
    Environment = var.environment
  }
}

resource "aws_lambda_function" "this" {
  publish = true

  function_name = local.function_name
  role          = var.role_arn
  package_type  = "Image"
  image_uri     = "${var.ecr_repository_url}:latest"
  # The application pipeline owns the code (see compute/lambda/tenant-account).
  lifecycle {
    ignore_changes = [image_uri]
  }
  architectures = ["arm64"]

  timeout     = 28
  memory_size = 256

  environment {
    variables = merge({
      ENVIRONMENT            = var.environment
      TENANT_TABLE_NAME      = var.tenant_table_name
      LOCATION_TABLE_NAME    = var.location_table_name
      LOCATION_ID_INDEX_NAME = var.location_id_index_name
      USER_TABLE_NAME        = var.user_table_name
      CONSENT_TABLE_NAME     = var.consent_table_name
      MARKETING_TABLE_NAME   = var.marketing_table_name
    }, var.retention_env)
  }

  tags = {
    Environment = var.environment
  }

  depends_on = [aws_cloudwatch_log_group.this]
}
