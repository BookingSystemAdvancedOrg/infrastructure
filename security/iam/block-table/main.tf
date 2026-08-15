# Execution role for the BlockTableFn Lambda.
#
# Three access levels: read-only on location (validates the location/table
# exists, business hours), read-only on user (a single GetItem on
# PK = USER#<sub> to confirm the caller's role and assigned location before
# authorizing the block), and full access on slot occupancy - this Lambda
# writes manual "source: manual_block" rows to hold a table out of online
# booking, and deletes them again on unblock.

data "aws_caller_identity" "current" {}

locals {
  function_name = var.environment == "prod" ? "block-table" : "${var.environment}-block-table"
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
  name = "location-and-user-table-read"
  role = aws_iam_role.this.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid    = "ReadLocationAndUserTables"
        Effect = "Allow"
        Action = [
          "dynamodb:Scan",
          "dynamodb:GetItem",
          "dynamodb:Query",
        ]
        Resource = [
          "${var.location_table_arn}",
          "${var.user_table_arn}",
        ]
      }
    ]
  })
}

resource "aws_iam_role_policy" "dynamodb_full" {
  name = "slot-occupancy-full-access"
  role = aws_iam_role.this.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid      = "FullAccessSlotOccupancyTable"
        Effect   = "Allow"
        Action   = "dynamodb:*"
        Resource = "${var.slot_occupancy_table_arn}"
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
