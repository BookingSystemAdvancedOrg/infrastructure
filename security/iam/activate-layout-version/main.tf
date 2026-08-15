# Execution role for the ActivateLayoutVersionFn Lambda.
#
# Per explicit request: full dynamodb:* on the published layout snapshot
# table.

data "aws_caller_identity" "current" {}

locals {
  function_name = var.environment == "prod" ? "activate-layout-version" : "${var.environment}-activate-layout-version"
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

resource "aws_iam_role_policy" "dynamodb_full" {
  name = "published-layout-snapshot-table-full-access"
  role = aws_iam_role.this.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid      = "FullAccessPublishedLayoutSnapshotTable"
        Effect   = "Allow"
        Action   = "dynamodb:*"
        Resource = "${var.published_layout_snapshot_table_arn}"
      }
    ]
  })
}

# Lets this Lambda create the one-time "expire-layout-version-<...>"
# schedule at cutover, same pattern as StripeWebhookFn's
# no-show-check schedule. CreateSchedule is scoped to that naming
# pattern in the default schedule group, not every schedule in the
# account. PassRole is scoped to the one role being handed to the
# Scheduler service, further restricted by the PassedToService condition
# so this permission can't be reused to pass that role to anything else.
#
# No scheduler:DeleteSchedule here yet - the full design calls for this
# Lambda to delete the pending schedule stored on the version being
# superseded before creating the new one. Add that action (scoped to the
# same schedule/expire-layout-version-* resource pattern) when that step
# is implemented, or a republish will leave the prior schedule orphaned.
resource "aws_iam_role_policy" "eventbridge_scheduler" {
  name = "create-expire-layout-version-schedule"
  role = aws_iam_role.this.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid      = "CreateExpireLayoutVersionSchedule"
        Effect   = "Allow"
        Action   = "scheduler:*"
        Resource = "arn:aws:scheduler:${var.region}:${data.aws_caller_identity.current.account_id}:schedule/default/expire-layout-version-*"
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
# No logs:CreateLogGroup - the log group is provisioned explicitly in
# compute/lambda/activate-layout-version (with a real retention period,
# not CloudWatch's "never expire" default), so the function only ever
# needs to write into it, never create it. Trade-off: if that log group
# were ever deleted outside Terraform, this role couldn't recreate it.
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
