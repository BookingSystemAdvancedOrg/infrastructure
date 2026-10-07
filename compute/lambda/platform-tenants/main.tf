# Operator-facing platform API (/platform/* - operator user pool JWT with
# the platform/admin scope, see network/api-gateway). The code lives in the
# sbs-admin repo (api/), whose pipeline pushes the image and updates this
# function - not in the backend application repo.
#
# Creating a tenant = one TransactWriteItems (PROFILE + SLUG# uniqueness row,
# status "provisioning") + StartExecution of the onboarding workflow. Every
# other provisioning step happens in the workflow, never in this Lambda.

locals {
  function_name = var.environment == "prod" ? "platform-tenants" : "${var.environment}-platform-tenants"
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
      ENVIRONMENT                     = var.environment
      TENANT_TABLE_NAME               = var.tenant_table_name
      LOCATION_TABLE_NAME             = var.location_table_name
      LOCATION_ID_INDEX_NAME          = var.location_id_index_name
      USER_TABLE_NAME                 = var.user_table_name
      USER_TENANT_INDEX_NAME          = var.user_tenant_index_name
      TENANT_USER_POOL_ID             = var.tenant_user_pool_id
      OWNER_GROUP_NAME                = var.owner_group_name
      ONBOARDING_STATE_MACHINE_ARN    = var.onboarding_state_machine_arn
      DOMAIN_ATTACH_STATE_MACHINE_ARN = var.domain_attach_state_machine_arn
      DOMAIN_DETACH_STATE_MACHINE_ARN = var.domain_detach_state_machine_arn
      OFFBOARDING_STATE_MACHINE_ARN   = var.offboarding_state_machine_arn
      STRIPE_SECRET_ARN               = var.stripe_secret_arn
      STRIPE_API_VERSION              = var.stripe_api_version
      PLATFORM_DOMAIN                 = var.platform_domain
      TENANT_DOMAIN_CNAME_TARGET      = var.tenant_domain_cname_target
      ADMIN_APP_URL                   = var.admin_app_url
      PLATFORM_ADMIN_APP_URL          = var.platform_admin_app_url
    }
  }

  tags = {
    Environment = var.environment
  }

  depends_on = [aws_cloudwatch_log_group.this]
}
