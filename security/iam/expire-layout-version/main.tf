# Execution role for the ExpireLayoutVersionFn Lambda.
#
# Per explicit request: full dynamodb:* on the published layout snapshot
# table. This is the Lambda targeted by the one-time EventBridge Schedule
# created at publish time — it fires at cutover and conditionally flips
# isCurrent = false on the superseded version.

data "aws_caller_identity" "current" {}

locals {
  function_name = var.environment == "prod" ? "expire-layout-version" : "${var.environment}-expire-layout-version"
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
  name = "published-layout-snapshot-table-full-access"
  role = aws_iam_role.this.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid      = "FullAccessPublishedLayoutSnapshotTable"
        Effect   = "Allow"
        Action   = "dynamodb:*"
        Resource = "${var.published_layout_snapshot_table_arn}"
      }
    ]
  })
}

# Scoped to exactly this function's own log group — not logs:* on everything.
#
# No logs:CreateLogGroup - the log group is provisioned explicitly in
# compute/lambda/expire-layout-version (with a real retention period, not
# CloudWatch's "never expire" default), so the function only ever needs to
# write into it, never create it. Trade-off: if that log group were ever
# deleted outside Terraform, this role couldn't recreate it.
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
