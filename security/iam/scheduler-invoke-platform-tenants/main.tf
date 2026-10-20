# Role that EventBridge Scheduler assumes for the daily dunning schedule of
# platform-tenants ({"financeTask": "dunning"}: suspend customers whose
# subscription has been past due too long, resume the ones that paid).
#
# NOT a Lambda execution role; it only lets scheduler.amazonaws.com invoke
# this one function.

data "aws_caller_identity" "current" {}

resource "aws_iam_role" "this" {
  name = var.environment == "prod" ? "scheduler-invoke-platform-tenants-role" : "${var.environment}-scheduler-invoke-platform-tenants-role"

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

resource "aws_iam_role_policy" "invoke_platform_tenants" {
  name = "invoke-platform-tenants-function"
  role = aws_iam_role.this.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid    = "InvokePlatformTenantsFunction"
        Effect = "Allow"
        Action = "lambda:InvokeFunction"
        Resource = [
          var.platform_tenants_lambda_arn,
          "${var.platform_tenants_lambda_arn}:*", # its versions and the "live" alias the schedule invokes
        ]
      }
    ]
  })
}
