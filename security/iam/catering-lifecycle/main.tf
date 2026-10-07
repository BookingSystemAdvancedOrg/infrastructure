# Execution role for the CateringLifecycleFn Lambda - owns everything that
# hangs off a status change or a point in time. Two triggers:
#
#   1. The catering-requests stream (storage/dynamodb/catering-requests):
#      creates/deletes the per-request timers, issues and finalizes the
#      Stripe invoice when a company order becomes "confirmed", releases
#      capacity on terminal statuses.
#   2. EventBridge Scheduler (one-off schedules in the catering schedule
#      group): owner reminder, request expiry, offer / signed-unpaid expiry,
#      day-before reminder.
#
# It is the ONLY function that creates or deletes catering schedules, so it
# is the only one holding scheduler permissions + iam:PassRole.

data "aws_caller_identity" "current" {}

locals {
  function_name = var.environment == "prod" ? "catering-lifecycle" : "${var.environment}-catering-lifecycle"
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

resource "aws_iam_role_policy" "stream_read" {
  name = "catering-requests-stream-read"
  role = aws_iam_role.this.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid    = "ReadCateringRequestsStream"
        Effect = "Allow"
        Action = [
          "dynamodb:DescribeStream",
          "dynamodb:GetRecords",
          "dynamodb:GetShardIterator",
          "dynamodb:ListStreams",
        ]
        Resource = "${var.catering_requests_stream_arn}"
      }
    ]
  })
}

resource "aws_iam_role_policy" "stream_dlq" {
  name = "catering-lifecycle-stream-dlq-send"
  role = aws_iam_role.this.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid    = "SendFailedBatchesToDlq"
        Effect = "Allow"
        Action = [
          "sqs:SendMessage",
        ]
        Resource = "${var.lifecycle_stream_dlq_arn}"
      }
    ]
  })
}

resource "aws_iam_role_policy" "catering_requests" {
  name = "catering-requests-table-full-access"
  role = aws_iam_role.this.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid      = "FullAccessCateringRequestsTable"
        Effect   = "Allow"
        Action   = "dynamodb:*"
        Resource = "${var.catering_requests_table_arn}"
      }
    ]
  })
}

resource "aws_iam_role_policy" "catering_request_history" {
  name = "catering-request-history-table-full-access"
  role = aws_iam_role.this.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid      = "FullAccessCateringRequestHistoryTable"
        Effect   = "Allow"
        Action   = "dynamodb:*"
        Resource = "${var.catering_request_history_table_arn}"
      }
    ]
  })
}

resource "aws_iam_role_policy" "location" {
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

resource "aws_iam_role_policy" "secrets" {
  name = "catering-secrets-read"
  role = aws_iam_role.this.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid    = "ReadStripeKey"
        Effect = "Allow"
        Action = [
          "secretsmanager:GetSecretValue",
        ]
        Resource = "${var.stripe_secret_arn}"
      }
    ]
  })
}

# Schedules are scoped to the dedicated catering schedule group, not the
# whole account. PassRole is limited to the one scheduler invoke role and
# only when it's handed to the Scheduler service.
resource "aws_iam_role_policy" "eventbridge_scheduler" {
  name = "manage-catering-schedules"
  role = aws_iam_role.this.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid    = "ManageCateringSchedules"
        Effect = "Allow"
        Action = [
          "scheduler:CreateSchedule",
          "scheduler:UpdateSchedule",
          "scheduler:DeleteSchedule",
          "scheduler:GetSchedule",
        ]
        Resource = "arn:aws:scheduler:${var.region}:${data.aws_caller_identity.current.account_id}:schedule/${var.schedule_group_name}/*"
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

# Lambda delivers this function's failed asynchronous (scheduled) invocations
# to the scheduled-invocation DLQ using THIS role, so it needs SendMessage on
# exactly that queue (compute/lambda/<name>: aws_lambda_function_event_invoke_config).
resource "aws_iam_role_policy" "scheduled_invocation_dlq" {
  name = "scheduled-invocation-dlq-send"
  role = aws_iam_role.this.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid      = "SendFailedScheduledInvocationsToDlq"
        Effect   = "Allow"
        Action   = "sqs:SendMessage"
        Resource = "${var.scheduled_invocation_dlq_arn}"
      }
    ]
  })
}
