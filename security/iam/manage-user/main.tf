# Execution role for the manage-user Lambda.
#
# Per explicit request: full dynamodb:* on the user table, rather than the
# scoped Scan/PutItem/UpdateItem/DeleteItem set that was recommended.
#
# Cognito access is scoped to the specific Admin* actions "manage-user"
# actually needs to run the full staff lifecycle - inviting (AdminCreateUser
# + AdminAddUserToGroup to assign staff/owner_user/super_user), updating,
# deactivating/reactivating, and removing someone - rather than a blanket
# cognito-idp:* wildcard, which would also grant things like deleting the
# user pool itself.

data "aws_caller_identity" "current" {}

locals {
  function_name = var.environment == "prod" ? "manage-user" : "${var.environment}-manage-user"
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

resource "aws_iam_role_policy" "dynamodb_full" {
  name = "user-table-full-access"
  role = aws_iam_role.this.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid      = "FullAccessUserTable"
        Effect   = "Allow"
        Action   = "dynamodb:*"
        Resource = "${var.user_table_arn}"
      }
    ]
  })
}

resource "aws_iam_role_policy" "cognito_user_management" {
  name = "cognito-user-management"
  role = aws_iam_role.this.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid    = "ManageStaffLifecycleInUserPool"
        Effect = "Allow"
        Action = [
          "cognito-idp:AdminCreateUser",
          "cognito-idp:AdminDeleteUser",
          "cognito-idp:AdminDisableUser",
          "cognito-idp:AdminEnableUser",
          "cognito-idp:AdminUpdateUserAttributes",
          "cognito-idp:AdminAddUserToGroup",
          "cognito-idp:AdminRemoveUserFromGroup",
          "cognito-idp:AdminGetUser",
          "cognito-idp:AdminListGroupsForUser",
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
