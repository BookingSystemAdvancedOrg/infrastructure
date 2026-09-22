# Execution role for the ListLayoutVersionFn Lambda.
#
# Least privilege: read-only, and only the published layout snapshot table.

data "aws_caller_identity" "current" {}

locals {
  function_name = var.environment == "prod" ? "list-layout-version" : "${var.environment}-list-layout-version"
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

resource "aws_iam_role_policy" "dynamodb" {
  name = "published-layout-snapshot-table"
  role = aws_iam_role.this.id

  # Allow the full DynamoDB action space on this table so the Lambda can
  # perform soft-archive writes (UpdateItem) in addition to its existing
  # read operations (Scan, GetItem, Query).
  #
  # DeleteItem is explicitly denied even though this endpoint is described
  # as a soft-archive (UpdateItem to set archivedAt / status fields). The
  # deny is a hard guardrail: if a future code path or misconfiguration
  # tried to issue a real delete, IAM blocks it regardless of what the
  # allow statement says. Explicit denies always win over allows in IAM.
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid      = "AllPublishedLayoutSnapshotActions"
        Effect   = "Allow"
        Action   = "dynamodb:*"
        Resource = "${var.published_layout_snapshot_table_arn}"
      },
      {
        Sid      = "DenyHardDelete"
        Effect   = "Deny"
        Action   = "dynamodb:DeleteItem"
        Resource = "${var.published_layout_snapshot_table_arn}"
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
