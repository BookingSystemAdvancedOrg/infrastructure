# Execution role for the DlqReplayFn Lambda - the scheduled job that drains
# the three dead-letter queues (storage/sqs/dead-letter) and redelivers each
# failed item to the Lambda that owns it:
#
#   catering-lifecycle-stream-dlq -> catering-lifecycle (records re-read from
#                                    the catering-requests stream)
#   notification-stream-dlq       -> notification (records re-read from the
#                                    reservation / order / catering-requests stream)
#   scheduled-invocation-dlq      -> the function named in the failure record:
#                                    catering-lifecycle, no-show-check,
#                                    reactivate-menu-item or expire-layout-version
#
# It holds no table permissions on purpose: it never does business work
# itself, it only redelivers. Invoke rights are limited to those five
# functions, so a crafted message can't make it call anything else.

data "aws_caller_identity" "current" {}

locals {
  function_name = var.environment == "prod" ? "dlq-replay" : "${var.environment}-dlq-replay"
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

resource "aws_iam_role_policy" "dlq" {
  name = "dlq-consume"
  role = aws_iam_role.this.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid    = "ConsumeDeadLetterQueues"
        Effect = "Allow"
        Action = [
          "sqs:ReceiveMessage",
          "sqs:DeleteMessage",
          "sqs:ChangeMessageVisibility",
          "sqs:GetQueueAttributes",
        ]
        Resource = [
          "${var.lifecycle_stream_dlq_arn}",
          "${var.notification_stream_dlq_arn}",
          "${var.scheduled_invocation_dlq_arn}",
        ]
      }
    ]
  })
}

resource "aws_iam_role_policy" "invoke" {
  name = "invoke-replay-targets"
  role = aws_iam_role.this.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid    = "RedeliverToOwningFunctions"
        Effect = "Allow"
        Action = [
          "lambda:InvokeFunction",
        ]
        Resource = [
          "${var.catering_lifecycle_function_arn}",
          "${var.catering_lifecycle_function_arn}:*",
          "${var.notification_function_arn}",
          "${var.notification_function_arn}:*",
          "${var.no_show_check_function_arn}",
          "${var.no_show_check_function_arn}:*",
          "${var.reactivate_menu_item_function_arn}",
          "${var.reactivate_menu_item_function_arn}:*",
          "${var.expire_layout_version_function_arn}",
          "${var.expire_layout_version_function_arn}:*",
        ]
      }
    ]
  })
}

resource "aws_iam_role_policy" "stream_read" {
  name = "dynamodb-streams-read"
  role = aws_iam_role.this.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid    = "ReReadFailedStreamRecords"
        Effect = "Allow"
        Action = [
          "dynamodb:DescribeStream",
          "dynamodb:GetShardIterator",
          "dynamodb:GetRecords",
        ]
        Resource = [
          "${var.catering_requests_stream_arn}",
          "${var.reservation_stream_arn}",
          "${var.order_stream_arn}",
        ]
      }
    ]
  })
}

resource "aws_iam_role_policy" "alerts" {
  name = "alerts-publish"
  role = aws_iam_role.this.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid    = "PublishEscalations"
        Effect = "Allow"
        Action = [
          "sns:Publish",
        ]
        Resource = "${var.alert_topic_arn}"
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
