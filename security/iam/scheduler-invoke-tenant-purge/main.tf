# Role that EventBridge Scheduler itself assumes when the recurring
# tenant-purge schedule fires, so it can invoke the purge Lambda.
#
# This is NOT a Lambda execution role - it's never assumed by a Lambda, so
# it has no CloudWatch Logs permission of its own. Its only job is letting
# the scheduler.amazonaws.com service call this one function.

data "aws_caller_identity" "current" {}

resource "aws_iam_role" "this" {
  name = var.environment == "prod" ? "scheduler-invoke-tenant-purge-role" : "${var.environment}-scheduler-invoke-tenant-purge-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect    = "Allow"
        Principal = { Service = "scheduler.amazonaws.com" }
        Action    = "sts:AssumeRole"
        Condition = {
          StringEquals = { "aws:SourceAccount" = data.aws_caller_identity.current.account_id }
        }
      }
    ]
  })

  tags = {
    Environment = var.environment
  }
}

resource "aws_iam_role_policy" "invoke_tenant_purge" {
  name = "invoke-tenant-purge-function"
  role = aws_iam_role.this.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid    = "InvokeTenantPurgeFunction"
        Effect = "Allow"
        Action = "lambda:InvokeFunction"
        Resource = [
          var.tenant_purge_lambda_arn,
          "${var.tenant_purge_lambda_arn}:*", # its versions and the "live" alias the schedule invokes
        ]
      }
    ]
  })
}
