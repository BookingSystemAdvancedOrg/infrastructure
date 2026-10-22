# Execution role for the guest-privacy Lambda (application
# functions/guest-privacy): the owner's privacy notice and consent
# withdrawals on a guest's behalf. The tenant-context read policy is
# attached in the root privacy-consent.tf.

data "aws_caller_identity" "current" {}

locals {
  function_name = var.environment == "prod" ? "guest-privacy" : "${var.environment}-guest-privacy"
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

resource "aws_iam_role_policy" "data" {
  name = "guest-privacy-data"
  role = aws_iam_role.this.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        # privacyNotice on the caller's own PROFILE row (the handler only
        # ever uses the tenant_id from the token).
        Sid      = "PrivacyNotice"
        Effect   = "Allow"
        Action   = ["dynamodb:GetItem", "dynamodb:UpdateItem"]
        Resource = var.tenant_table_arn
      },
      {
        # Append-only: Query and PutItem, never UpdateItem or DeleteItem.
        Sid      = "ConsentLog"
        Effect   = "Allow"
        Action   = ["dynamodb:Query", "dynamodb:PutItem"]
        Resource = var.consent_table_arn
      },
      {
        # The subscriber list follows a withdrawal (status unsubscribed).
        Sid      = "SubscriberStatus"
        Effect   = "Allow"
        Action   = "dynamodb:UpdateItem"
        Resource = var.marketing_table_arn
      },
    ]
  })
}

resource "aws_iam_role_policy" "logs" {
  name = "cloudwatch-logs"
  role = aws_iam_role.this.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid      = "WriteOwnLogGroup"
        Effect   = "Allow"
        Action   = ["logs:CreateLogStream", "logs:PutLogEvents"]
        Resource = "arn:aws:logs:${var.region}:${data.aws_caller_identity.current.account_id}:log-group:/aws/lambda/${local.function_name}:*"
      }
    ]
  })
}
