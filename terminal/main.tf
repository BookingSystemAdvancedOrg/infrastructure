# Card payments at the till (backlog 23): staff take in-person card payments
# from the admin app on the restaurant's Stripe Terminal readers (S700/S710,
# server-driven, no SDK). Readers are registered in Booqy Console
# (docs/handoff/TERMINAL.md); this is the payment side.
# Application side: functions/terminal-payments, shared/card_payments.py,
# shared/card_messages.py.
#
# Everything the feature owns lives in this module except the ECR repository
# (top-level module, CI bootstraps images from it), the API routes
# (network/api-gateway/terminal-routes.tf) and the Stripe webhook endpoint
# (payments/stripe "terminal", which points at the Function URL below).
#
#   terminal-payments  admin API /locations/{locationId}/card-payments[/...] (JWT)
#                      + Function URL: Stripe Connect events for the readers
#
# Card payments are stored in the order table (CARD#<date>#<id>, next to the
# location's orders), so retention, guest privacy, tenant purge and
# Statistik reach them with the access they already have.

data "aws_caller_identity" "current" {}

locals {
  prefix   = var.environment == "prod" ? "" : "${var.environment}-"
  account  = data.aws_caller_identity.current.account_id
  function = "terminal-payments"
  name     = "${local.prefix}${local.function}"
}

resource "aws_iam_role" "fn" {
  name = "${local.name}-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect    = "Allow"
      Principal = { Service = "lambda.amazonaws.com" }
      Action    = "sts:AssumeRole"
    }]
  })

  tags = {
    Environment = var.environment
  }
}

# Least privilege. Tenant/location reads and the staff location check come
# from the shared tenant-context policy (config.tf tenant_aware_role_names,
# staff_check_role_names).
resource "aws_iam_role_policy" "fn" {
  name = "${local.function}-access"
  role = aws_iam_role.fn.id
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        # Card payment records and their pointers (CARD#, CID#), and the
        # unpaid order being paid (cardPaymentId; settling it confirms it).
        # Item-level only: no Scan, no Delete, no table-level actions.
        Sid      = "CardPaymentsInOrderTable"
        Effect   = "Allow"
        Action   = ["dynamodb:GetItem", "dynamodb:PutItem", "dynamodb:UpdateItem", "dynamodb:Query"]
        Resource = var.order_table_arn
      },
      {
        # The platform Stripe key (Stripe-Account header = the restaurant)
        # and this endpoint's webhook signing secret.
        Sid      = "ReadStripeSecrets"
        Effect   = "Allow"
        Action   = "secretsmanager:GetSecretValue"
        Resource = [var.stripe_secret_arn, var.webhook_secret_arn]
      },
    ]
  })
}

resource "aws_iam_role_policy" "logs" {
  name = "cloudwatch-logs"
  role = aws_iam_role.fn.id
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Sid      = "WriteLogs"
      Effect   = "Allow"
      Action   = ["logs:CreateLogStream", "logs:PutLogEvents"]
      Resource = "arn:aws:logs:${var.region}:${local.account}:log-group:/aws/lambda/${local.name}:*"
    }]
  })
}

resource "aws_cloudwatch_log_group" "fn" {
  name              = "/aws/lambda/${local.name}"
  retention_in_days = 30

  tags = {
    Environment = var.environment
  }
}

resource "aws_lambda_function" "fn" {
  function_name = local.name
  role          = aws_iam_role.fn.arn
  package_type  = "Image"
  image_uri     = "${var.ecr_repository_url}:latest"
  publish       = true
  architectures = ["arm64"]
  # A checkout is a few Stripe calls in a row; API Gateway stops at 30 s.
  timeout     = 29
  memory_size = 256

  # The application pipeline releases <repo>:<sha>; Terraform sets only the first image.
  lifecycle {
    ignore_changes = [image_uri]
  }

  environment {
    variables = {
      ENVIRONMENT                        = var.environment
      TENANT_TABLE_NAME                  = var.tenant_table_name
      LOCATION_TABLE_NAME                = var.location_table_name
      LOCATION_ID_INDEX_NAME             = var.location_id_index_name
      USER_TABLE_NAME                    = var.user_table_name
      ORDER_TABLE_NAME                   = var.order_table_name
      STRIPE_SECRET_ARN                  = var.stripe_secret_arn
      STRIPE_API_VERSION                 = var.stripe_api_version
      TERMINAL_STRIPE_WEBHOOK_SECRET_ARN = var.webhook_secret_arn
    }
  }

  depends_on = [aws_cloudwatch_log_group.fn, aws_iam_role_policy.logs]

  tags = {
    Environment = var.environment
  }
}

# Callers invoke "live"; CodeDeploy moves it (orchestration/lambda-releases).
resource "aws_lambda_alias" "live" {
  name             = "live"
  function_name    = aws_lambda_function.fn.function_name
  function_version = aws_lambda_function.fn.version

  lifecycle {
    ignore_changes = [function_version, routing_config]
  }
}

# Stripe's Connect endpoint for the readers posts here. Auth NONE: the
# handler trusts only the Stripe-Signature header. The signing secret comes
# from Secrets Manager (payments/stripe writes it after creating the
# endpoint from this URL), so there is no dependency cycle. AWS adds the two
# resource-policy statements a public URL needs.
resource "aws_lambda_function_url" "webhook" {
  function_name      = aws_lambda_function.fn.function_name
  qualifier          = aws_lambda_alias.live.name
  authorization_type = "NONE"
  invoke_mode        = "BUFFERED"
}

resource "aws_cloudwatch_metric_alarm" "errors" {
  alarm_name        = "${local.name}-errors"
  alarm_description = "terminal-payments crashed (Lambda errors): a card payment at the till or a Stripe reader event failed. Check the terminal-payments logs; Stripe retries webhook deliveries."
  namespace         = "AWS/Lambda"
  metric_name       = "Errors"
  dimensions        = { FunctionName = aws_lambda_function.fn.function_name }

  statistic           = "Sum"
  period              = 300
  evaluation_periods  = 1
  comparison_operator = "GreaterThanThreshold"
  threshold           = 0
  treat_missing_data  = "notBreaching"

  alarm_actions = [var.alert_topic_arn]

  tags = {
    Environment = var.environment
  }
}
