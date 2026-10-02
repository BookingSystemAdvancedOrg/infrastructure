locals {
  function_name = var.environment == "prod" ? "manage-menu" : "${var.environment}-manage-menu"
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
  function_name = local.function_name
  role          = var.role_arn
  package_type  = "Image"
  image_uri     = "${var.ecr_repository_url}:latest"
  architectures = ["arm64"]

  timeout     = 28
  memory_size = 512

  environment {
    variables = {
      ENVIRONMENT                       = var.environment
      MENU_TABLE_NAME                   = var.menu_table_name
      SCHEDULER_INVOKE_ROLE_ARN         = var.scheduler_invoke_role_arn         # the Role for EventBridge Scheduler to assume when invoking reactivate-menu-item
      REACTIVATE_MENU_ITEM_FUNCTION_ARN = var.reactivate_menu_item_function_arn # the Lambda function ARN for reactivate-menu-item, the Scheduler target for the end-of-window schedule
    }
  }

  tags = {
    Environment = var.environment
  }
}
