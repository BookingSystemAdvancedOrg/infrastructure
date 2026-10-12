# Execution role for the get-order Lambda.
#
# Guest routes: reads an order by key (pointer + order, GetItem) and, while
# the order still waits for payment, settles it from the Checkout Session
# (UpdateItem on the order and the day's number counter). Stripe key to
# look the session up; link signing key (status token) from
# security/secrets/reservations; tenant/location reads from tenant-context.

data "aws_caller_identity" "current" {}

locals {
  function_name = var.environment == "prod" ? "get-order" : "${var.environment}-get-order"
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

resource "aws_iam_role_policy" "dynamodb_read" {
  name = "order-table-read"
  role = aws_iam_role.this.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid    = "ReadAndSettleOrders"
        Effect = "Allow"
        Action = [
          "dynamodb:GetItem",
          "dynamodb:UpdateItem",
        ]
        Resource = "${var.order_table_arn}"
      }
    ]
  })
}

# Platform Stripe key - to look up a pending order's Checkout Session on
# the restaurant's connected account.
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
        Resource = var.stripe_secret_arn
      }
    ]
  })
}

# Scoped to exactly this function's own log group — not logs:* on everything.
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
