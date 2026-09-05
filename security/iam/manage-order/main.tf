# Execution role for the manage-order Lambda.
#
# Same structure as manage-menu's role - one IAM role per Lambda, never
# shared. This Lambda is the staff/owner/super-admin write-and-query path
# for orders (status updates through the kitchen lifecycle, the day's-
# orders dashboard Query, cancellations), so unlike manage-menu it needs
# read actions too - dynamodb:* scoped to the one order table covers both
# without ever reaching another table.

data "aws_caller_identity" "current" {}

locals {
  function_name = var.environment == "prod" ? "manage-order" : "${var.environment}-manage-order"
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

resource "aws_iam_role_policy" "dynamodb_crud" {
  name = "order-table-crud"
  role = aws_iam_role.this.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid      = "CRUDOrderTable"
        Effect   = "Allow"
        Action   = "dynamodb:*"
        Resource = "${var.order_table_arn}"
      }
    ]
  })
}

# Scoped to exactly this function's own log group - not logs:* on everything.
#
# No logs:CreateLogGroup - the log group is provisioned explicitly in
# compute/lambda/manage-order with a real retention period instead of
# CloudWatch's "never expire" default.
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
