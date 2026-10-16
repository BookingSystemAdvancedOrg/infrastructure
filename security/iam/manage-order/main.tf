# Execution role for the manage-order Lambda.
#
# Same structure as manage-menu's role - one IAM role per Lambda, never
# shared. This Lambda is the staff/owner write-and-query path (own tenant only)
# for orders: the day's-orders Query, reading one order by key (GetItem)
# and status moves / refunds (UpdateItem) - item-level only, never
# table-level actions.

data "aws_caller_identity" "current" {}

locals {
  function_name = var.environment == "prod" ? "manage-order" : "${var.environment}-manage-order"
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

resource "aws_iam_role_policy" "dynamodb_crud" {
  name = "order-table-crud"
  role = aws_iam_role.this.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid    = "ItemAccessOrderTable"
        Effect = "Allow"
        Action = [
          "dynamodb:GetItem",
          "dynamodb:Query",
          "dynamodb:UpdateItem",
        ]
        Resource = "${var.order_table_arn}"
      }
    ]
  })
}

# Pausing orders writes orderingPausedUntil on the location row (item
# update by key only).
resource "aws_iam_role_policy" "location_pause" {
  name = "location-ordering-pause"
  role = aws_iam_role.this.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid      = "PauseOrdering"
        Effect   = "Allow"
        Action   = "dynamodb:UpdateItem"
        Resource = var.location_table_arn
      }
    ]
  })
}

# Platform Stripe key - refunds when staff cancel a paid order.
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

# Scoped to exactly this function's own log group - not logs:* on everything.
#
# No logs:CreateLogGroup - the log group is provisioned explicitly in
# compute/lambda/manage-order with a real retention period instead of
# CloudWatch's "never expire" default.
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
