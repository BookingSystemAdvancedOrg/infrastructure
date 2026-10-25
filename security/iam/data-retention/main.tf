# Execution role for the data-retention Lambda (application
# functions/data-retention): deletes or anonymises guest data whose
# retention period is over, and turns withdrawn consent into suppression
# records. Plus the role EventBridge Scheduler assumes to start it.
#
# DynamoDB can't scope a role to "rows that are old enough", so the Lambda
# decides per item (shared/retention.py) and only its schedule and its own
# continuation can invoke it. Item-level actions only: no table can be
# deleted or reconfigured with it, and there is no Scan.
#
# Not here, on purpose: the finance table (Booqy's invoicing), Stripe, the
# catering documents bucket (7-year Object Lock), the tenant PROFILE rows
# (read through the list index only), the user table and Cognito.

data "aws_caller_identity" "current" {}

locals {
  function_name = var.environment == "prod" ? "data-retention" : "${var.environment}-data-retention"
  function_arn  = "arn:aws:lambda:${var.region}:${data.aws_caller_identity.current.account_id}:function:${local.function_name}"
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
  name = "expire-guest-data"
  role = aws_iam_role.this.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        # Lists the restaurants (GSI1, the same list Booqy Console shows).
        Sid      = "ListTenants"
        Effect   = "Allow"
        Action   = "dynamodb:Query"
        Resource = "${var.tenant_table_arn}/index/GSI1"
      },
      {
        # A restaurant's locations (PK TENANT#<t>).
        Sid      = "ListLocations"
        Effect   = "Allow"
        Action   = "dynamodb:Query"
        Resource = var.location_table_arn
      },
      {
        # Bookings, orders and catering requests: read, anonymise (UpdateItem
        # strips the guest fields, sets ttl), delete when the time is up.
        Sid    = "ExpireGuestRows"
        Effect = "Allow"
        Action = [
          "dynamodb:Query",
          "dynamodb:UpdateItem",
          "dynamodb:DeleteItem",
        ]
        Resource = var.guest_table_arns
      },
      {
        # Withdrawn consent -> one suppression record; expired suppressions go.
        Sid    = "ConsentLog"
        Effect = "Allow"
        Action = [
          "dynamodb:Query",
          "dynamodb:PutItem",
          "dynamodb:DeleteItem",
        ]
        Resource = [var.consent_table_arn, "${var.consent_table_arn}/index/*"]
      },
      {
        # The subscriber row of a guest whose consent is now only a suppression;
        # unconfirmed sign-ups are deleted, bounced/complained rows lose the
        # address (Query the TENANT#<t>#SUB partition, UpdateItem strips it).
        Sid      = "ExpireSubscriberRows"
        Effect   = "Allow"
        Action   = ["dynamodb:Query", "dynamodb:UpdateItem", "dynamodb:DeleteItem"]
        Resource = var.marketing_table_arn
      },
      {
        Sid      = "NotifyOperators"
        Effect   = "Allow"
        Action   = "sns:Publish"
        Resource = var.alert_topic_arn
      },
      {
        Sid      = "ContinueItself"
        Effect   = "Allow"
        Action   = "lambda:InvokeFunction"
        Resource = [local.function_arn, "${local.function_arn}:*"]
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

# Assumed by EventBridge Scheduler (not a Lambda): may invoke this one
# function and nothing else.
resource "aws_iam_role" "scheduler" {
  name = var.environment == "prod" ? "scheduler-invoke-data-retention-role" : "${var.environment}-scheduler-invoke-data-retention-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect    = "Allow"
        Principal = { Service = "scheduler.amazonaws.com" }
        Action    = "sts:AssumeRole"
        Condition = {
          StringEquals = { "aws:SourceAccount" = data.aws_caller_identity.current.account_id }
        }
      }
    ]
  })

  tags = {
    Environment = var.environment
  }
}

resource "aws_iam_role_policy" "scheduler" {
  name = "invoke-data-retention-function"
  role = aws_iam_role.scheduler.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid      = "InvokeDataRetentionFunction"
        Effect   = "Allow"
        Action   = "lambda:InvokeFunction"
        Resource = [local.function_arn, "${local.function_arn}:*"]
      }
    ]
  })
}
