# Execution role for the ReactivateMenuItemFn Lambda.
#
# This is the Lambda targeted by the one-time EventBridge Schedule created
# by ManageMenuFn when staff sets a menu item inactive for a date window
# (security/iam/manage-menu's eventbridge_scheduler policy) — it fires at
# the end of that window and flips the item's `active` attribute back to
# true. Scoped to exactly dynamodb:UpdateItem on the menu table - this
# Lambda does one conditional write per invocation, never a Scan/Query/
# GetItem/PutItem/Delete.

data "aws_caller_identity" "current" {}

locals {
  function_name = var.environment == "prod" ? "reactivate-menu-item" : "${var.environment}-reactivate-menu-item"
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

resource "aws_iam_role_policy" "dynamodb_update" {
  name = "menu-table-update-item"
  role = aws_iam_role.this.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid      = "UpdateMenuTableItem"
        Effect   = "Allow"
        Action   = "dynamodb:UpdateItem"
        Resource = "${var.menu_table_arn}"
      }
    ]
  })
}

# Scoped to exactly this function's own log group — not logs:* on everything.
#
# No logs:CreateLogGroup - the log group is provisioned explicitly in
# compute/lambda/reactivate-menu-item (with a real retention period, not
# CloudWatch's "never expire" default), so the function only ever needs to
# write into it, never create it. Trade-off: if that log group were ever
# deleted outside Terraform, this role couldn't recreate it.
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
