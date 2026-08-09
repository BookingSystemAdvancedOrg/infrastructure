# Execution role for the CreatePendingReservationFn Lambda.
#
# Two access levels: read-only on location (booking rules) and the
# published layout snapshot (which tables exist), full access on slot
# occupancy and reservation - this Lambda is what atomically holds a slot
# and writes the new pending reservation.
#
# Also full access to payment delinquency - this is the Lambda that checks
# whether the booking customer's phone number has any unpaid debt before
# letting the booking proceed.

data "aws_caller_identity" "current" {}

locals {
  function_name = var.environment == "prod" ? "create-pending-reservation" : "${var.environment}-create-pending-reservation"
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
  name = "location-and-published-layout-snapshot-read"
  role = aws_iam_role.this.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid    = "ReadLocationAndPublishedLayoutSnapshotTables"
        Effect = "Allow"
        Action = [
          "dynamodb:Scan",
          "dynamodb:GetItem",
          "dynamodb:Query",
        ]
        Resource = [
          "${var.location_table_arn}",
          "${var.published_layout_snapshot_table_arn}",
        ]
      }
    ]
  })
}

resource "aws_iam_role_policy" "dynamodb_full" {
  name = "slot-occupancy-and-reservation-full-access"
  role = aws_iam_role.this.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid    = "FullAccessSlotOccupancyAndReservationTables"
        Effect = "Allow"
        Action = "dynamodb:*"
        Resource = [
          "${var.slot_occupancy_table_arn}",
          "${var.reservation_table_arn}",
        ]
      }
    ]
  })
}

resource "aws_iam_role_policy" "payment_delinquency_full" {
  name = "payment-delinquency-full-access"
  role = aws_iam_role.this.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid      = "FullAccessPaymentDelinquencyTable"
        Effect   = "Allow"
        Action   = "dynamodb:*"
        Resource = "${var.payment_delinquency_table_arn}"
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
