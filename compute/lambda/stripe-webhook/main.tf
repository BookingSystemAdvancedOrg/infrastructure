locals {
  function_name = var.environment == "prod" ? "stripe-webhook" : "${var.environment}-stripe-webhook"
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
      ENVIRONMENT                    = var.environment
      LOCATION_TABLE_NAME            = var.location_table_name
      RESERVATION_TABLE_NAME         = var.reservation_table_name
      PAYMENT_DELINQUENCY_TABLE_NAME = var.payment_delinquency_table_name
      SCHEDULER_INVOKE_ROLE_ARN      = var.scheduler_invoke_role_arn  # the Role for EventBridge Scheduler to assume when invoking the Lambda, so the Lambda can be invoked by Scheduler
      NO_SHOW_CHECK_FUNCTION_ARN     = var.no_show_check_function_arn # the Lambda function ARN for the no-show check Lambda, so this Lambda can invoke it to check for no-shows
      STRIPE_WEBHOOK_SECRET          = var.stripe_webhook_secret      # signing secret the handler checks the Stripe-Signature header against - see the authorization_type = NONE comment below for why this is the actual authentication boundary
    }
  }

  tags = {
    Environment = var.environment
  }
}

# Stripe reaches this Lambda through the HTTP API route POST /webhooks/stripe/reservation
# (see network/api-gateway), not a Function URL. The route is
# unauthenticated at the gateway - the real authentication boundary is the
# handler's verification of the Stripe-Signature header against
# STRIPE_WEBHOOK_SECRET. The Function URL this module used to declare
# was removed when the webhook endpoint itself moved into Terraform
# (payments/stripe): a Function URL is derived from this function, and this
# function's environment needs the endpoint's signing secret - a dependency
# cycle. The API route's URL depends only on the API itself, so the whole
# chain applies in one pass.
