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
  # Every code/config change Terraform makes is published as a new version.
  # Callers never invoke the function directly - they invoke the "live"
  # alias (alias.tf).
  publish = true

  function_name = local.function_name
  role          = var.role_arn
  package_type  = "Image"
  image_uri     = "${var.ecr_repository_url}:latest"
  architectures = ["arm64"]

  timeout     = 28
  memory_size = 512

  environment {
    variables = {
      TENANT_TABLE_NAME              = var.tenant_table_name
      LOCATION_ID_INDEX_NAME         = var.location_id_index_name
      ENVIRONMENT                    = var.environment
      LOCATION_TABLE_NAME            = var.location_table_name
      RESERVATION_TABLE_NAME         = var.reservation_table_name
      PAYMENT_DELINQUENCY_TABLE_NAME = var.payment_delinquency_table_name
      SCHEDULER_INVOKE_ROLE_ARN      = var.scheduler_invoke_role_arn  # the Role for EventBridge Scheduler to assume when invoking the Lambda, so the Lambda can be invoked by Scheduler
      NO_SHOW_CHECK_FUNCTION_ARN     = var.no_show_check_function_arn # the Lambda function ARN for the no-show check Lambda, so this Lambda can invoke it to check for no-shows
      STRIPE_WEBHOOK_SECRET_ARN      = var.stripe_webhook_secret_arn  # Secrets Manager secret holding the endpoint signing secret (whsec_...), filled in by payments/stripe
    }
  }

  tags = {
    Environment = var.environment
  }
}

# Stripe calls this function directly through its Function URL - no API
# Gateway in front. Stripe can't sign requests with SigV4 and has no Cognito
# token, so the URL is deliberately unauthenticated (authorization_type =
# NONE); the real authentication boundary is the handler's verification of
# the Stripe-Signature header against the endpoint's signing secret.
#
# The secret reaches the handler via Secrets Manager (STRIPE_WEBHOOK_SECRET_ARN), not
# as a plain environment variable: the Stripe endpoint is created from this
# URL, the URL is derived from this function, so the function's environment
# can't also hold the endpoint's secret (a dependency cycle). It CAN hold
# the ARN of a secret that payments/stripe fills in after creating the
# endpoint. The handler reads it at cold start and re-reads once on a
# signature mismatch (covers an endpoint being re-created with a new secret).
#
# For authorization_type = NONE, AWS adds the two resource-policy statements
# a public URL needs (lambda:InvokeFunctionUrl, and lambda:InvokeFunction
# with InvokedViaFunctionUrl = true) when the URL is created.
resource "aws_lambda_function_url" "this" {
  function_name      = aws_lambda_function.this.function_name
  qualifier          = aws_lambda_alias.live.name
  authorization_type = "NONE"
  invoke_mode        = "BUFFERED"
}
