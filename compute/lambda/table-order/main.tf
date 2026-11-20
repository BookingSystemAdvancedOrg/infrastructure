locals {
  function_name = var.environment == "prod" ? "table-order" : "${var.environment}-table-order"
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

# Staff take orders at the table (Bordsbeställning): tabs in the table-order
# table, kitchen and bar tickets through the print table (shared/routing +
# shared/printing, dispatched synchronously, no stream). No payment, no
# Stripe: the guest pays in the restaurant's own system.
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
  # resets image_uri to :latest.
  lifecycle {
    ignore_changes = [image_uri]
  }
  architectures = ["arm64"]

  timeout     = 28
  memory_size = 512

  environment {
    variables = {
      TABLE_ORDER_TABLE_NAME               = var.table_order_table_name
      MENU_TABLE_NAME                      = var.menu_table_name
      PRINT_TABLE_NAME                     = var.print_table_name
      PUBLISHED_LAYOUT_SNAPSHOT_TABLE_NAME = var.published_layout_snapshot_table_name
      RESERVATION_TABLE_NAME               = var.reservation_table_name
      TENANT_TABLE_NAME                    = var.tenant_table_name
      LOCATION_TABLE_NAME                  = var.location_table_name
      LOCATION_ID_INDEX_NAME               = var.location_id_index_name
      USER_TABLE_NAME                      = var.user_table_name
      ENVIRONMENT                          = var.environment
    }
  }

  tags = {
    Environment = var.environment
  }
}
