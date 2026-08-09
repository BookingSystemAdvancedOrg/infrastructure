# Execution role for the StripeWebhookFn Lambda.
#
# Read-only on location, full access on reservation - this Lambda reacts
# to Stripe events (e.g. setup_intent.succeeded, payment succeeded/failed)
# and updates the matching reservation's status and Stripe reference IDs.
#
# Also full access to payment delinquency - this is the Lambda that marks
# a debt record paid once the customer completes payment via the Stripe
# Payment Link sent after a failed no-show/late-cancel charge.

data "aws_caller_identity" "current" {}

locals {
  function_name = var.environment == "prod" ? "stripe-webhook" : "${var.environment}-stripe-webhook"
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
  name = "location-table-read"
  role = aws_iam_role.this.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid    = "ReadLocationTable"
        Effect = "Allow"
        Action = [
          "dynamodb:Scan",
          "dynamodb:GetItem",
          "dynamodb:Query",
        ]
        Resource = "${var.location_table_arn}"
      }
    ]
  })
}

resource "aws_iam_role_policy" "dynamodb_full" {
  name = "reservation-table-full-access"
  role = aws_iam_role.this.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid      = "FullAccessReservationTable"
        Effect   = "Allow"
        Action   = "dynamodb:*"
        Resource = "${var.reservation_table_arn}"
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

# Lets this Lambda create the one-time "no-show-check-<reservationId>"
# schedule after a reservation is confirmed. CreateSchedule is scoped to
# that naming pattern in the default schedule group, not every schedule in
# the account. PassRole is scoped to the one role being handed to the
# Scheduler service, further restricted by the PassedToService condition
# so this permission can't be reused to pass that role to anything else.
resource "aws_iam_role_policy" "eventbridge_scheduler" {
  name = "create-no-show-check-schedule"
  role = aws_iam_role.this.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid      = "CreateNoShowCheckSchedule"
        Effect   = "Allow"
        Action   = "scheduler:*"
        Resource = "arn:aws:scheduler:${var.region}:${data.aws_caller_identity.current.account_id}:schedule/default/no-show-check-*"
      },
      {
        Sid      = "PassSchedulerInvokeRole"
        Effect   = "Allow"
        Action   = "iam:PassRole"
        Resource = "${var.scheduler_invoke_role_arn}"
        Condition = {
          StringEquals = {
            "iam:PassedToService" = "scheduler.amazonaws.com"
          }
        }
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
