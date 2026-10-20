# Execution role for the finance-rollup Lambda: the nightly job behind the
# Finance page (see the function's docstring in the application repo,
# functions/finance-rollup/app.py).
#
# Read-only on everything that belongs to customers: it lists tenants and
# locations and counts bookings and orders (Query, never Scan, no writes)
# and reads the campaign counters in the marketing table. It writes only
# the finance table. Cost Explorer and Logs Insights have no resource-level
# scoping for the read calls themselves (Resource "*" by AWS design);
# StartQuery is limited to the Lambda log groups it counts requests in.

data "aws_caller_identity" "current" {}

locals {
  function_name = var.environment == "prod" ? "finance-rollup" : "${var.environment}-finance-rollup"
  function_arn  = "arn:aws:lambda:${var.region}:${data.aws_caller_identity.current.account_id}:function:${local.function_name}"
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

resource "aws_iam_role_policy" "data" {
  name = "finance-figures"
  role = aws_iam_role.this.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        # The per-day rows, invoices (read for the revenue sums), platform
        # totals and the job status.
        Sid    = "FinanceTable"
        Effect = "Allow"
        Action = [
          "dynamodb:GetItem",
          "dynamodb:Query",
          "dynamodb:PutItem",
          "dynamodb:UpdateItem",
          "dynamodb:BatchWriteItem",
        ]
        Resource = var.finance_table_arn
      },
      {
        # Lists tenants (GSI1) and reads profiles (plan, status, billing).
        Sid    = "ListTenants"
        Effect = "Allow"
        Action = [
          "dynamodb:GetItem",
          "dynamodb:Query",
        ]
        Resource = [var.tenant_table_arn, "${var.tenant_table_arn}/index/*"]
      },
      {
        # A customer's locations, then that day's bookings and orders per
        # location (emails, SMS and marketing emails are counted by the
        # senders themselves on the day rows).
        Sid      = "CountUsage"
        Effect   = "Allow"
        Action   = "dynamodb:Query"
        Resource = [var.location_table_arn, var.reservation_table_arn, var.order_table_arn]
      },
      {
        # The account's cost per service and day. No resource-level
        # permissions exist for this API.
        Sid      = "ReadCost"
        Effect   = "Allow"
        Action   = "ce:GetCostAndUsage"
        Resource = "*"
      },
      {
        # Requests per customer: one Logs Insights query over the tenant-aware
        # Lambdas' log groups.
        Sid      = "CountRequestsInLogs"
        Effect   = "Allow"
        Action   = ["logs:StartQuery", "logs:StopQuery"]
        Resource = [for name in var.log_group_names : "arn:aws:logs:${var.region}:${data.aws_caller_identity.current.account_id}:log-group:${name}:*"]
      },
      {
        # Results are fetched by query id - the API has no resource to scope.
        Sid      = "ReadQueryResults"
        Effect   = "Allow"
        Action   = "logs:GetQueryResults"
        Resource = "*"
      },
      {
        Sid      = "NotifyOperators"
        Effect   = "Allow"
        Action   = "sns:Publish"
        Resource = var.alert_topic_arn
      },
      {
        # Carries on in a new invocation when a run gets close to its timeout.
        Sid      = "ContinueItself"
        Effect   = "Allow"
        Action   = "lambda:InvokeFunction"
        Resource = [local.function_arn, "${local.function_arn}:*"]
      },
    ]
  })
}

# Scoped to exactly this function's own log group - not logs:* on everything.
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
