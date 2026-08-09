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
      SCHEDULER_INVOKE_ROLE_ARN      = var.scheduler_invoke_role_arn # the Role for EventBridge Scheduler to assume when invoking the Lambda, so the Lambda can be invoked by Scheduler
      NO_SHOW_CHECK_FUNCTION_ARN     = var.no_show_check_function_arn  # the Lambda function ARN for the no-show check Lambda, so this Lambda can invoke it to check for no-shows
    }
  }

  tags = {
    Environment = var.environment
  }
}

# Stripe calls this directly, not through API Gateway - it can't sign
# requests with AWS SigV4 the way API Gateway would expect, and it isn't a
# logged-in user of this app so it has no Cognito token either. A Function
# URL gives it a plain public HTTPS endpoint instead: this is the URL
# registered as the webhook destination in the Stripe Dashboard.
#
# authorization_type = NONE means AWS itself doesn't gate the request - the
# real check happens inside the handler, which verifies the
# Stripe-Signature header against STRIPE_WEBHOOK_SECRET and rejects
# anything that doesn't match. NONE here is what makes that verification
# necessary, not optional.
resource "aws_lambda_function_url" "this" {
  function_name      = aws_lambda_function.this.function_name
  authorization_type = "NONE"
}

# Without this, AWS rejects every call to the URL above before it even
# reaches the handler - authorization_type = NONE only means "no AWS-side
# auth required", it doesn't by itself open the door to unauthenticated
# callers. This resource-based policy is what actually does that, scoped
# narrowly to lambda:InvokeFunctionUrl (not general InvokeFunction) so it
# can't be used to invoke this Lambda through any other path.
resource "aws_lambda_permission" "function_url_public_invoke" {
  statement_id           = "AllowPublicInvokeFunctionUrl"
  action                 = "lambda:InvokeFunctionUrl"
  function_name          = aws_lambda_function.this.function_name
  principal              = "*"
  function_url_auth_type = "NONE"
}
