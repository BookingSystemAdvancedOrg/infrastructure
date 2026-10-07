# Role that EventBridge Scheduler itself assumes when a catering schedule
# fires (owner reminder, request expiry, offer / signed-unpaid expiry,
# day-before reminder), so it can invoke the catering-lifecycle Lambda.
#
# This is NOT a Lambda execution role - it's never assumed by a Lambda, so
# it has no CloudWatch Logs permission of its own. Its jobs are invoking
# that one function and, when every retry fails, dropping the schedule's
# input into the scheduler DLQ (Scheduler sends DLQ messages with this
# role, not a queue policy).
#
# The schedule group lives here too: it's the scope both this role's
# purpose and catering-lifecycle's scheduler permissions are written
# against, and it lets every catering timer be listed or cleaned up as one
# set instead of being mixed into the account's default group.

locals {
  prefix = var.environment == "prod" ? "" : "${var.environment}-"
}

resource "aws_scheduler_schedule_group" "catering" {
  name = "${local.prefix}catering"

  tags = {
    Environment = var.environment
  }
}

resource "aws_iam_role" "this" {
  name = "${local.prefix}scheduler-invoke-catering-lifecycle-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect    = "Allow"
        Principal = { Service = "scheduler.amazonaws.com" }
        Action    = "sts:AssumeRole"
      }
    ]
  })

  tags = {
    Environment = var.environment
  }
}

resource "aws_iam_role_policy" "invoke_catering_lifecycle" {
  name = "invoke-catering-lifecycle-function"
  role = aws_iam_role.this.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid    = "InvokeCateringLifecycleFunction"
        Effect = "Allow"
        Action = "lambda:InvokeFunction"
        Resource = [
          "${var.catering_lifecycle_lambda_arn}",
          "${var.catering_lifecycle_lambda_arn}:*", # its versions and the "live" alias callers invoke
        ]
      },
      {
        Sid      = "SendUndeliverableToDlq"
        Effect   = "Allow"
        Action   = "sqs:SendMessage"
        Resource = "${var.scheduler_dlq_arn}"
      }
    ]
  })
}
