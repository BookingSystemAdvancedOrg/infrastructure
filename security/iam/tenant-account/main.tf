# Execution role for the TenantAccountFn Lambda - an owner's view of their own
# tenant (/tenant routes, tenant pool JWT): plan, usage, Stripe onboarding
# status, domains; edit sender name / reply-to / branding; get a fresh
# Stripe onboarding link.
#
# Tenant-table writes are limited AT THE IAM LEVEL to the profile fields an
# owner may change (dynamodb:Attributes condition below) - even a bug in this
# Lambda can't let an owner change their plan, limits, status or Stripe
# account. Reads of the tenant row come from the shared tenant-context policy.

data "aws_caller_identity" "current" {}

locals {
  function_name = var.environment == "prod" ? "tenant-account" : "${var.environment}-tenant-account"
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

resource "aws_iam_role_policy" "location_table" {
  name = "location-table-read"
  role = aws_iam_role.this.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid    = "ReadLocationTable"
        Effect = "Allow"
        Action = [
          "dynamodb:GetItem",
          "dynamodb:Query",
        ]
        Resource = [
          "${var.location_table_arn}",
          "${var.location_table_arn}/index/*",
        ]
      }
    ]
  })
}

resource "aws_iam_role_policy" "tenant_profile_edit" {
  name = "tenant-profile-self-service"
  role = aws_iam_role.this.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid    = "OwnerEditableProfileFieldsOnly"
        Effect = "Allow"
        Action = [
          "dynamodb:UpdateItem",
        ]
        Resource = "${var.tenant_table_arn}"
        Condition = {
          "ForAllValues:StringEquals" = {
            "dynamodb:Attributes" = ["PK", "SK", "senderName", "replyToEmail", "branding", "notifications", "updatedAt", "updatedBy"]
          }
          # ALL_OLD / ALL_NEW would hand back the whole row (plan, Stripe
          # ids...) through an update - only the touched attributes may return.
          StringEqualsIfExists = {
            "dynamodb:ReturnValues" = ["NONE", "UPDATED_OLD", "UPDATED_NEW"]
          }
        }
      }
    ]
  })
}

resource "aws_iam_role_policy" "stripe_secret" {
  name = "platform-stripe-secret"
  role = aws_iam_role.this.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid    = "ReadPlatformStripeKey"
        Effect = "Allow"
        Action = [
          "secretsmanager:GetSecretValue",
        ]
        Resource = "${var.stripe_secret_arn}"
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
