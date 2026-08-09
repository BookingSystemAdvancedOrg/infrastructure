# Execution role for the ManageAuthFn Lambda.
#
# Covers the three flows this function handles against the Cognito user
# pool:
#   - Login: cognito-idp:InitiateAuth with USER_PASSWORD_AUTH
#   - Silent refresh: cognito-idp:InitiateAuth with REFRESH_TOKEN_AUTH, to
#     mint new access/id tokens without the user re-entering credentials
#   - First-time "registration": when a super-user/owner-user creates a new
#     staff account, Cognito issues a temporary password by email (via SES,
#     handled by manage-user). The invited user's first login trips a
#     NEW_PASSWORD_REQUIRED challenge, which this function completes with
#     cognito-idp:RespondToAuthChallenge to set their real password.
#
# No AdminCreateUser/AdminSetUserPassword here - creating the user account
# itself is manage-user's job, not this function's.

data "aws_caller_identity" "current" {}

locals {
  function_name = var.environment == "prod" ? "manage-auth" : "${var.environment}-manage-auth"
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

resource "aws_iam_role_policy" "cognito_auth" {
  name = "cognito-user-pool-auth"
  role = aws_iam_role.this.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid    = "LoginRefreshAndCompleteNewPasswordChallenge"
        Effect = "Allow"
        Action = [
          "cognito-idp:InitiateAuth",
          "cognito-idp:RespondToAuthChallenge",
        ]
        Resource = "${var.user_pool_arn}"
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
