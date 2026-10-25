# GET /insights: a restaurant's own figures for a period (Statistik in the
# admin app). Reads the rolled-up days from the insights table and computes
# today live; owners get everything, staff only the operations figures
# (no amounts) when the owner allows it. Code: the application repo,
# functions/insights.

locals {
  function_name = var.environment == "prod" ? "insights" : "${var.environment}-insights"
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
  # The application pipeline owns the code (see compute/lambda/catering-settings).
  lifecycle {
    ignore_changes = [image_uri]
  }
  architectures = ["arm64"]

  timeout     = 28
  memory_size = 1024

  environment {
    variables = {
      ENVIRONMENT                          = var.environment
      INSIGHTS_TABLE_NAME                  = var.insights_table_name
      TENANT_TABLE_NAME                    = var.tenant_table_name
      LOCATION_TABLE_NAME                  = var.location_table_name
      LOCATION_ID_INDEX_NAME               = var.location_id_index_name
      USER_TABLE_NAME                      = var.user_table_name
      RESERVATION_TABLE_NAME               = var.reservation_table_name
      ORDER_TABLE_NAME                     = var.order_table_name
      CATERING_REQUESTS_TABLE_NAME         = var.catering_requests_table_name
      PUBLISHED_LAYOUT_SNAPSHOT_TABLE_NAME = var.published_layout_snapshot_table_name
      MARKETING_TABLE_NAME                 = var.marketing_table_name
    }
  }

  tags = {
    Environment = var.environment
  }

  depends_on = [aws_cloudwatch_log_group.this]
}
