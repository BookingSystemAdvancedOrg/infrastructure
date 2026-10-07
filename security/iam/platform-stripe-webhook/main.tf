# Execution role for the PlatformStripeWebhookFn Lambda - Stripe events about
# the platform itself rather than a restaurant's orders:
#
#   - Connect events (account.updated, account.application.deauthorized):
#     a restaurant finishing / losing Stripe onboarding -> PROFILE.stripe.*
#   - Platform-account billing events (customer.subscription.*): the
#     restaurant's own SaaS subscription -> plan + limits on PROFILE.
#
# Two Stripe endpoints (connect scope and account scope), two signing
# secrets, one function.

data "aws_caller_identity" "current" {}

locals {
  function_name = var.environment == "prod" ? "platform-stripe-webhook" : "${var.environment}-platform-stripe-webhook"
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

resource "aws_iam_role_policy" "tenant_table" {
  name = "tenant-table-write"
  role = aws_iam_role.this.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        # Item-level only - no table-level actions (DeleteTable, UpdateTable,
        # PITR) for an application role, and no Scan.
        Sid    = "ItemAccessTenantTable"
        Effect = "Allow"
        Action = [
          "dynamodb:GetItem",
          "dynamodb:Query",
          "dynamodb:UpdateItem",
        ]
        Resource = [
          "${var.tenant_table_arn}",
          "${var.tenant_table_arn}/index/*",
        ]
      }
    ]
  })
}

resource "aws_iam_role_policy" "secrets" {
  name = "platform-stripe-secrets"
  role = aws_iam_role.this.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid    = "ReadWebhookAndApiSecrets"
        Effect = "Allow"
        Action = [
          "secretsmanager:GetSecretValue",
        ]
        Resource = [
          "${var.connect_webhook_secret_arn}",
          "${var.billing_webhook_secret_arn}",
          "${var.stripe_secret_arn}",
        ]
      }
    ]
  })
}

# Scoped to exactly this function's own log group - not logs:* on everything.
# No logs:CreateLogGroup: the log group is provisioned explicitly alongside
# the function (compute/lambda/<name>) with a real retention period.
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
