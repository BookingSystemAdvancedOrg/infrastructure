# Role that EventBridge Scheduler itself assumes when a "no-show-check-*"
# schedule fires, so it can invoke the no-show-check Lambda.
#
# This is NOT a Lambda execution role - it's never assumed by a Lambda, so
# it has no CloudWatch Logs permission of its own. Its only job is letting
# the scheduler.amazonaws.com service call this one function.

resource "aws_iam_role" "this" {
  name = var.environment == "prod" ? "scheduler-invoke-no-show-check-role" : "${var.environment}-scheduler-invoke-no-show-check-role"

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

resource "aws_iam_role_policy" "invoke_no_show_check" {
  name = "invoke-no-show-check-function"
  role = aws_iam_role.this.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid      = "InvokeNoShowCheckFunction"
        Effect   = "Allow"
        Action   = "lambda:InvokeFunction"
        Resource = "${var.no_show_check_lambda_arn}"
      }
    ]
  })
}
