# Execution role for the manage-menu Lambda.
#
# Same structure as get-menu's role, but its own separate resource — one
# IAM role per Lambda, never shared. This Lambda creates, edits, and
# deletes menu items (including setting `imageKey` after a successful S3
# upload) — it operates on items it already has the key for, so it needs
# no Scan/Query/GetItem, only the three write actions below.

data "aws_caller_identity" "current" {}

locals {
  function_name = var.environment == "prod" ? "manage-menu" : "${var.environment}-manage-menu"
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

resource "aws_iam_role_policy" "dynamodb_crud" {
  name = "menu-table-crud"
  role = aws_iam_role.this.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid      = "CRUDMenuTable"
        Effect   = "Allow"
        Action   = "dynamodb:*"
        Resource = "${var.menu_table_arn}"
      }
    ]
  })
}

# Lets this Lambda create/update/delete the one-time
# "reactivate-menu-item-<...>" schedule when staff set a menu item inactive
# for a date window, same pattern as ActivateLayoutVersionFn's
# expire-layout-version schedule. CreateSchedule/UpdateSchedule/
# DeleteSchedule are all scoped to that naming pattern in the default
# schedule group, not every schedule in the account. Update+Delete are
# included from the start (not just Create) so a staff member changing or
# clearing the dates before the schedule fires re-targets or removes the
# existing schedule instead of leaving an orphan that silently flips the
# item back on later - activate-layout-version's own role only has Create
# today and flags that exact gap in its comments; this role doesn't repeat
# it. PassRole is scoped to the one role being handed to the Scheduler
# service, further restricted by the PassedToService condition so this
# permission can't be reused to pass that role to anything else.
resource "aws_iam_role_policy" "eventbridge_scheduler" {
  name = "manage-reactivate-menu-item-schedule"
  role = aws_iam_role.this.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid      = "ManageReactivateMenuItemSchedule"
        Effect   = "Allow"
        Action   = ["scheduler:CreateSchedule", "scheduler:UpdateSchedule", "scheduler:DeleteSchedule", "scheduler:GetSchedule"]
        Resource = "arn:aws:scheduler:${var.region}:${data.aws_caller_identity.current.account_id}:schedule/default/reactivate-menu-item-*"
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
