# Role that EventBridge Scheduler itself assumes when a
# "reactivate-menu-item-*" schedule fires, so it can invoke the
# reactivate-menu-item Lambda.
#
# This is NOT a Lambda execution role - it's never assumed by a Lambda, so
# it has no CloudWatch Logs permission of its own. Its only job is letting
# the scheduler.amazonaws.com service call this one function.

resource "aws_iam_role" "this" {
  name = var.environment == "prod" ? "scheduler-invoke-reactivate-menu-item-role" : "${var.environment}-scheduler-invoke-reactivate-menu-item-role"

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

resource "aws_iam_role_policy" "invoke_reactivate_menu_item" {
  name = "invoke-reactivate-menu-item-function"
  role = aws_iam_role.this.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid    = "InvokeReactivateMenuItemFunction"
        Effect = "Allow"
        Action = "lambda:InvokeFunction"
        Resource = [
          "${var.reactivate_menu_item_lambda_arn}",
          "${var.reactivate_menu_item_lambda_arn}:*", # its versions and the "live" alias callers invoke
        ]
      }
    ]
  })
}
