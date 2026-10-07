# Receives the platform Stripe endpoints' events (payments/stripe) through its
# own Function URL - no API Gateway, same pattern as the other Stripe webhook
# Lambdas. Paths: /connect (connected-account events) and /billing (platform
# account subscription events); each verifies against its own secret.

locals {
  function_name = var.environment == "prod" ? "platform-stripe-webhook" : "${var.environment}-platform-stripe-webhook"
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
      ENVIRONMENT                = var.environment
      TENANT_TABLE_NAME          = var.tenant_table_name
      CONNECT_WEBHOOK_SECRET_ARN = var.connect_webhook_secret_arn
      BILLING_WEBHOOK_SECRET_ARN = var.billing_webhook_secret_arn
      STRIPE_SECRET_ARN          = var.stripe_secret_arn
      STRIPE_API_VERSION         = var.stripe_api_version
    }
  }

  tags = {
    Environment = var.environment
  }

  depends_on = [aws_cloudwatch_log_group.this]
}

# Stripe calls this function directly through its Function URL - no API
# Gateway in front. Stripe can't sign requests with SigV4 and has no Cognito
# token, so the URL is deliberately unauthenticated (authorization_type =
# NONE); the real authentication boundary is the handler's verification of
# the Stripe-Signature header against the endpoint's signing secret.
resource "aws_lambda_function_url" "this" {
  function_name      = aws_lambda_function.this.function_name
  authorization_type = "NONE"
  invoke_mode        = "BUFFERED"
}
