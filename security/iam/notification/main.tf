# Execution role for the NotificationFn Lambda.
#
# Invoked off the reservation table's DynamoDB Stream (see
# notify_on_reservation_status_change in storage/dynamodb/reservation) to
# text and, for failed-charge statuses, email the customer.
#
# Scoped to exactly the four stream-read actions the event source mapping's
# polling needs - not dynamodb:*, which would also grant table-item actions
# (GetItem, PutItem, Scan, etc.) this Lambda never uses, since it only ever
# reacts to records the stream hands it and never queries the live table.

data "aws_caller_identity" "current" {}

locals {
  function_name = var.environment == "prod" ? "notification" : "${var.environment}-notification"
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

resource "aws_iam_role_policy" "dynamodb_stream_read" {
  name = "reservation-stream-read"
  role = aws_iam_role.this.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid    = "ReadReservationStream"
        Effect = "Allow"
        Action = [
          "dynamodb:DescribeStream",
          "dynamodb:GetRecords",
          "dynamodb:GetShardIterator",
          "dynamodb:ListStreams",
        ]
        Resource = "${var.reservation_stream_arn}"
      }
    ]
  })
}

# SNS phone-number publishing (SMS) has no per-number ARN to scope to -
# AWS requires Resource = "*" for direct-to-phone-number sns:Publish calls,
# since an arbitrary customer phone number isn't a resource that exists in
# your account.
resource "aws_iam_role_policy" "sns_publish" {
  name = "sns-publish-sms"
  role = aws_iam_role.this.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid      = "PublishSmsToCustomer"
        Effect   = "Allow"
        Action   = "sns:Publish"
        Resource = "*"
      }
    ]
  })
}

resource "aws_iam_role_policy" "ses_send_email" {
  name = "ses-send-email"
  role = aws_iam_role.this.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid      = "SendEmailFromNoReplyIdentity"
        Effect   = "Allow"
        Action   = "ses:SendEmail"
        Resource = "${var.ses_identity_arn}"
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
