# Execution role for the create-location Lambda.
#
# Per established pattern: full dynamodb:* on the location table. Plus a
# narrow write on the tenant table for the plan's location quota (below).

data "aws_caller_identity" "current" {}

locals {
  function_name = var.environment == "prod" ? "create-location" : "${var.environment}-create-location"
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
  name = "location-table-full-access"
  role = aws_iam_role.this.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid      = "FullAccessLocationTable"
        Effect   = "Allow"
        Action   = "dynamodb:*"
        Resource = "${var.location_table_arn}"
      }
    ]
  })
}

# Plan limit on locations. Creating a location is ONE TransactWriteItems:
#   Update TENANT#<t>/PROFILE  SET locationCount = locationCount + 1
#     IF status = active AND locationCount < entitlements.maxLocations
#   Put    TENANT#<t>/LOCATION#<id>  IF attribute_not_exists(PK)
# so two owners clicking "add location" at once can never exceed the plan.
# Only the item-level actions a transaction uses on the tenant table - this
# function can't read other tenants' rows beyond the shared tenant-context
# policy, and can't Put/Delete tenant rows at all.
resource "aws_iam_role_policy" "tenant_location_quota" {
  name = "tenant-location-quota"
  role = aws_iam_role.this.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid    = "CountLocationsAgainstPlan"
        Effect = "Allow"
        Action = [
          "dynamodb:UpdateItem",
          "dynamodb:ConditionCheckItem",
        ]
        Resource = "${var.tenant_table_arn}"
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
