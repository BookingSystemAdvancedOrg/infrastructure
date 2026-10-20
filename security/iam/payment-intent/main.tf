# Execution role for the payment-intent Lambda.
#
# POST /order: writes the order + its pointer (one transaction - Put per
# item), stores the Checkout Session id / marks a rejected checkout failed
# (UpdateItem), reads the order back (GetItem). Prices come from the menu
# table (BatchGetItem, read only). Tenant/location reads come from the
# shared tenant-context policy; the link signing key from
# security/secrets/reservations.

data "aws_caller_identity" "current" {}

locals {
  function_name = var.environment == "prod" ? "payment-intent" : "${var.environment}-payment-intent"
}

resource "aws_iam_role" "this" {
  name = "${local.function_name}-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect    = "Allow"
        Principal = { Service = "lambda.amazonaws.com" }
        Action    = "sts:AssumeRole"
      }
    ]
  })

  tags = {
    Environment = var.environment
  }
}

resource "aws_iam_role_policy" "dynamodb_full" {
  name = "order-table-full-access"
  role = aws_iam_role.this.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid    = "ItemAccessOrderTable"
        Effect = "Allow"
        Action = [
          "dynamodb:GetItem",
          "dynamodb:PutItem",
          "dynamodb:UpdateItem",
        ]
        Resource = "${var.order_table_arn}"
      }
    ]
  })
}

# The platform Stripe key lives in Secrets Manager, not in this function's
# environment - an env var is readable by anyone with
# lambda:GetFunctionConfiguration, and with Stripe Connect this key can act
# on every restaurant's connected account.
resource "aws_iam_role_policy" "stripe_secret" {
  name = "platform-stripe-secret"
  role = aws_iam_role.this.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid      = "ReadPlatformStripeKey"
        Effect   = "Allow"
        Action   = "secretsmanager:GetSecretValue"
        Resource = "${var.stripe_secret_arn}"
      }
    ]
  })
}

# Prices are read from the menu - never trusted from the request.
resource "aws_iam_role_policy" "menu_read" {
  name = "menu-table-read"
  role = aws_iam_role.this.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid      = "ReadMenuPrices"
        Effect   = "Allow"
        Action   = "dynamodb:BatchGetItem"
        Resource = var.menu_table_arn
      }
    ]
  })
}

# Public order form: the Turnstile secret (bot check) and the attempt
# counters - item updates only, on that one table.
resource "aws_iam_role_policy" "order_protection" {
  name = "online-order-protection"
  role = aws_iam_role.this.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid      = "ReadTurnstileSecret"
        Effect   = "Allow"
        Action   = "secretsmanager:GetSecretValue"
        Resource = var.turnstile_secret_arn
      },
      {
        Sid      = "CountOrderAttempts"
        Effect   = "Allow"
        Action   = "dynamodb:UpdateItem"
        Resource = var.request_guard_table_arn
      }
    ]
  })
}

# Scoped to exactly this function's own log group - not logs:* on everything.
#
# No logs:CreateLogGroup - the log group is expected to be provisioned
# explicitly alongside this Lambda's function resource (same pattern as
# compute/lambda/activate-layout-version), with a real retention period
# instead of CloudWatch's "never expire" default. Until that function
# module exists, this role has no way to create its own log group -
# deploying this Lambda without one first means it can't write any logs
# at all.
resource "aws_iam_role_policy" "logs" {
  name = "cloudwatch-logs"
  role = aws_iam_role.this.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid    = "WriteOwnLogGroup"
        Effect = "Allow"
        Action = [
          "logs:CreateLogStream",
          "logs:PutLogEvents",
        ]
        Resource = "arn:aws:logs:${var.region}:${data.aws_caller_identity.current.account_id}:log-group:/aws/lambda/${local.function_name}:*"
      }
    ]
  })
}
