# Role that EventBridge Scheduler itself assumes when an
# "expire-layout-version-*" schedule fires, so it can invoke the
# expire-layout-version Lambda.
#
# This is NOT a Lambda execution role - it's never assumed by a Lambda, so
# it has no CloudWatch Logs permission of its own. Its only job is letting
# the scheduler.amazonaws.com service call this one function.

resource "aws_iam_role" "this" {
  name = var.environment == "prod" ? "scheduler-invoke-expire-layout-version-role" : "${var.environment}-scheduler-invoke-expire-layout-version-role"

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

resource "aws_iam_role_policy" "invoke_expire_layout_version" {
  name = "invoke-expire-layout-version-function"
  role = aws_iam_role.this.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid      = "InvokeExpireLayoutVersionFunction"
        Effect   = "Allow"
        Action   = "lambda:InvokeFunction"
        Resource = "${var.expire_layout_version_lambda_arn}"
      }
    ]
  })
}
