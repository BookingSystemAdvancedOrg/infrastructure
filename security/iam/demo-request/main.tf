# Execution role for the demo-request Lambda (compute/lambda/demo-request).
#
# Least privilege: its own log stream, and ses:SendEmail only for mail FROM
# the platform's no-reply address. No DynamoDB, nothing else - the request is
# emailed, not stored.

data "aws_caller_identity" "current" {}

locals {
  function_name = var.environment == "prod" ? "demo-request" : "${var.environment}-demo-request"
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

# No logs:CreateLogGroup: the log group is provisioned with the function.
resource "aws_iam_role_policy" "logs" {
  name = "cloudwatch-logs"
  role = aws_iam_role.this.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid      = "WriteOwnLogGroup"
        Effect   = "Allow"
        Action   = ["logs:CreateLogStream", "logs:PutLogEvents"]
        Resource = "arn:aws:logs:${var.region}:${data.aws_caller_identity.current.account_id}:log-group:/aws/lambda/${local.function_name}:*"
      }
    ]
  })
}

resource "aws_iam_role_policy" "ses" {
  name = "ses-send"
  role = aws_iam_role.this.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid      = "SendFromNoReplyIdentity"
        Effect   = "Allow"
        Action   = "ses:SendEmail"
        Resource = var.ses_identity_arn
      },
      {
        # SES also authorizes against the RECIPIENT's identity when it is a
        # verified identity (the sales address in the SES sandbox) - any
        # identity in this account, but only for mail from the no-reply address.
        Sid      = "SendToVerifiedRecipientIdentities"
        Effect   = "Allow"
        Action   = "ses:SendEmail"
        Resource = "arn:aws:ses:${var.region}:${data.aws_caller_identity.current.account_id}:identity/*"
        Condition = {
          StringLike = {
            "ses:FromAddress" = [var.from_address, "*<${var.from_address}>"]
          }
        }
      }
    ]
  })
}
