# Execution role for the table-order Lambda (staff take orders at the table).
#
# One role per Lambda, never shared. Item-level actions only, base tables
# only (no index, no stream, no table-level actions). TransactWriteItems is
# authorised per item action (PutItem, UpdateItem, DeleteItem,
# ConditionCheckItem), so it needs no action of its own. Tenant, location
# and user reads come from the shared tenant-context policy (config.tf).
# No Stripe, no secrets, no events: Booqy takes no payment for a tab.

data "aws_caller_identity" "current" {}

locals {
  function_name = var.environment == "prod" ? "table-order" : "${var.environment}-table-order"
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
  name = "table-order-data"
  role = aws_iam_role.this.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        # Tabs, one-open-per-table locks, idempotency rows, the STATE poll row.
        Sid    = "TableOrderItems"
        Effect = "Allow"
        Action = [
          "dynamodb:GetItem",
          "dynamodb:PutItem",
          "dynamodb:UpdateItem",
          "dynamodb:DeleteItem",
          "dynamodb:Query",
          "dynamodb:BatchGetItem",
          "dynamodb:ConditionCheckItem",
        ]
        Resource = var.table_order_table_arn
      },
      {
        # Dishes and categories: the staff menu and server-side pricing.
        Sid      = "ReadMenu"
        Effect   = "Allow"
        Action   = ["dynamodb:GetItem", "dynamodb:BatchGetItem", "dynamodb:Query"]
        Resource = var.menu_table_arn
      },
      {
        # Station routing, kitchen/bar tickets and print jobs (put once).
        Sid      = "PrintTickets"
        Effect   = "Allow"
        Action   = ["dynamodb:GetItem", "dynamodb:PutItem", "dynamodb:UpdateItem", "dynamodb:Query"]
        Resource = var.print_table_arn
      },
      {
        # The active floor plan: which tables exist and their labels.
        Sid      = "ReadPublishedLayout"
        Effect   = "Allow"
        Action   = "dynamodb:GetItem"
        Resource = var.published_layout_snapshot_table_arn
      },
      {
        # Today's bookings, to show which guest sits at a table.
        Sid      = "ReadReservations"
        Effect   = "Allow"
        Action   = ["dynamodb:Query", "dynamodb:GetItem"]
        Resource = var.reservation_table_arn
      },
    ]
  })
}

# Scoped to exactly this function's own log group. No logs:CreateLogGroup:
# the log group is provisioned in compute/lambda/table-order with a real
# retention period.
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
