locals {
  function_name = var.environment == "prod" ? "webhook-payment-intent" : "${var.environment}-webhook-payment-intent"
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
      ENVIRONMENT                 = var.environment
      ORDER_TABLE_NAME            = var.order_table_name
      ORDER_STRIPE_WEBHOOK_SECRET = var.order_stripe_webhook_secret # signing secret the handler checks the Stripe-Signature header against - see the authorization_type = NONE comment below for why this is the actual authentication boundary
    }
  }

  tags = {
    Environment = var.environment
  }
}

# Stripe reaches this Lambda through the HTTP API route POST /webhooks/stripe/order
# (see network/api-gateway), not a Function URL. The route is
# unauthenticated at the gateway - the real authentication boundary is the
# handler's verification of the Stripe-Signature header against
# ORDER_STRIPE_WEBHOOK_SECRET. The Function URL this module used to declare
# was removed when the webhook endpoint itself moved into Terraform
# (payments/stripe): a Function URL is derived from this function, and this
# function's environment needs the endpoint's signing secret - a dependency
# cycle. The API route's URL depends only on the API itself, so the whole
# chain applies in one pass.
