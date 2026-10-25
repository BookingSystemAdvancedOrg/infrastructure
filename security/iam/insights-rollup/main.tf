# Execution role for the insights-rollup Lambda: the nightly job behind
# Statistik in the admin app (see the function's docstring in the
# application repo, functions/insights-rollup/app.py).
#
# Read-only on everything that belongs to restaurants: it lists tenants and
# locations and reads each location's bookings, orders, catering requests
# and published layout (Query/GetItem, never Scan, no writes), and the
# website visit counters in the marketing table (the STATS partitions only).
# It writes only the insights table.

data "aws_caller_identity" "current" {}

locals {
  function_name = var.environment == "prod" ? "insights-rollup" : "${var.environment}-insights-rollup"
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
  name = "insights-figures"
  role = aws_iam_role.this.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        # One row per location and day, overwritten on every run.
        Sid    = "InsightsTable"
        Effect = "Allow"
        Action = [
          "dynamodb:GetItem",
          "dynamodb:Query",
          "dynamodb:PutItem",
          "dynamodb:BatchWriteItem",
        ]
        Resource = var.insights_table_arn
      },
      {
        # Lists tenants (GSI1) and reads their profiles (status, features).
        Sid    = "ListTenants"
        Effect = "Allow"
        Action = [
          "dynamodb:GetItem",
          "dynamodb:Query",
        ]
        Resource = [var.tenant_table_arn, "${var.tenant_table_arn}/index/*"]
      },
      {
        # A tenant's locations (hours, time zone, lunch split), then each
        # day's bookings, orders, catering requests and the layout's tables.
        Sid    = "ReadLocationData"
        Effect = "Allow"
        Action = [
          "dynamodb:GetItem",
          "dynamodb:Query",
        ]
        Resource = [
          var.location_table_arn,
          var.reservation_table_arn,
          var.order_table_arn,
          var.catering_requests_table_arn,
          var.published_layout_snapshot_table_arn,
        ]
      },
      {
        # Website visits per day: only the TENANT#<t>#STATS partitions,
        # never subscribers, templates or campaigns.
        Sid      = "ReadVisitCounters"
        Effect   = "Allow"
        Action   = "dynamodb:Query"
        Resource = var.marketing_table_arn
        Condition = {
          "ForAllValues:StringLike" = {
            "dynamodb:LeadingKeys" = ["TENANT#*#STATS"]
          }
        }
      },
      {
        # Carries on in a new invocation when a run gets close to its timeout.
        Sid      = "ContinueItself"
        Effect   = "Allow"
        Action   = "lambda:InvokeFunction"
        Resource = [local.function_arn, "${local.function_arn}:*"]
      },
    ]
  })
}

# Scoped to exactly this function's own log group - not logs:* on everything.
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
