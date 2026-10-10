# Execution role for the ReservationRemindersFn Lambda - every 15 minutes it
# marks bookings due a reminder (reminderSentAt + a "reminder" notice, one
# conditional UpdateItem each; NotificationFn sends the message off the
# Reservation stream) and expires card-guarantee bookings whose card was
# never confirmed (tables released in one transaction). Tenant rows come from the shared tenant-context policy.

data "aws_caller_identity" "current" {}

locals {
  function_name = var.environment == "prod" ? "reservation-reminders" : "${var.environment}-reservation-reminders"
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

resource "aws_iam_role_policy" "tables" {
  name = "reminder-tables"
  role = aws_iam_role.this.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        # Lists every location (small table, once per run).
        Sid      = "ListLocations"
        Effect   = "Allow"
        Action   = "dynamodb:Scan"
        Resource = var.location_table_arn
      },
      {
        # Due reminders (Query + conditional UpdateItem) and expired card
        # guarantees (GetItem, transaction Update/Delete of the booking and
        # its PENDING# marker).
        Sid    = "BookingsRemindersAndExpiry"
        Effect = "Allow"
        Action = [
          "dynamodb:Query",
          "dynamodb:GetItem",
          "dynamodb:UpdateItem",
          "dynamodb:DeleteItem",
          "dynamodb:ConditionCheckItem",
        ]
        Resource = var.reservation_table_arn
      },
      {
        # Releasing an expired booking's table holds and bumping the locks.
        Sid    = "ReleaseExpiredHolds"
        Effect = "Allow"
        Action = [
          "dynamodb:BatchGetItem",
          "dynamodb:UpdateItem",
          "dynamodb:DeleteItem",
          "dynamodb:ConditionCheckItem",
        ]
        Resource = var.slot_occupancy_table_arn
      }
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
