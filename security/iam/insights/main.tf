# Execution role for the insights Lambda (GET /insights): a restaurant's own
# figures for a period, read from the insights table, with today computed
# live from the operational tables (application repo, functions/insights).
#
# Read-only. The tenant comes from the token (shared/tenant.py, the shared
# tenant-context policy is attached in the root config); every key it reads
# is LOCATION#<one of that tenant's locations>. No access to the finance
# table: the operator's figures never reach a restaurant.

data "aws_caller_identity" "current" {}

locals {
  function_name = var.environment == "prod" ? "insights" : "${var.environment}-insights"
}

resource "aws_iam_role" "this" {
  name = var.environment == "prod" ? "insights-role" : "${var.environment}-insights-role"

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
  name = "insights-read"
  role = aws_iam_role.this.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        # The rolled-up days.
        Sid      = "ReadInsights"
        Effect   = "Allow"
        Action   = ["dynamodb:GetItem", "dynamodb:Query"]
        Resource = var.insights_table_arn
      },
      {
        # "Alla platser": the tenant's own locations (its TENANT#<t> partition).
        Sid      = "ListOwnLocations"
        Effect   = "Allow"
        Action   = "dynamodb:Query"
        Resource = var.location_table_arn
      },
      {
        # Today (and any day the nightly run has not reached yet), computed
        # live from that day's bookings, orders, catering and layout.
        Sid    = "ReadToday"
        Effect = "Allow"
        Action = ["dynamodb:GetItem", "dynamodb:Query"]
        Resource = [
          var.reservation_table_arn,
          var.order_table_arn,
          var.catering_requests_table_arn,
          var.published_layout_snapshot_table_arn,
        ]
      },
      {
        # Today's website visits: the STATS partitions only.
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
        Sid    = "WriteLogs"
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
