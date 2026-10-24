# Accounting export (Bokföring): the owner's BAS account mapping (stored on
# the location item, attribute `accounting`) and the SIE 4 / CSV export of
# one balanced verifikation per business day. Application side:
# functions/accounting, shared/accounting.py, shared/accounting_export.py,
# docs/ACCOUNTING-EXPORT.md.
#
# Read only on the money: the function only reads orders, card payments,
# reservations (card guarantee fees), catering requests and offers, the
# Kassa journal and the connected account's Stripe balance transactions.
# Its one write is the mapping on the caller's own location item.

data "aws_caller_identity" "current" {}

locals {
  prefix   = var.environment == "prod" ? "" : "${var.environment}-"
  account  = data.aws_caller_identity.current.account_id
  function = "accounting"
  name     = "${local.prefix}${local.function}"
}

resource "aws_iam_role" "fn" {
  name = "${local.name}-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect    = "Allow"
      Principal = { Service = "lambda.amazonaws.com" }
      Action    = "sts:AssumeRole"
    }]
  })

  tags = {
    Environment = var.environment
  }
}

# Least privilege. Tenant/location reads come from the shared tenant-context
# policy (config.tf tenant_aware_role_names). Query/GetItem only on the
# money tables: no PutItem, UpdateItem or DeleteItem there.
resource "aws_iam_role_policy" "fn" {
  name = "${local.function}-access"
  role = aws_iam_role.fn.id
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        # The mapping only: the update may touch nothing but `accounting`.
        Sid      = "SaveAccountMapping"
        Effect   = "Allow"
        Action   = "dynamodb:UpdateItem"
        Resource = var.location_table_arn
        Condition = {
          "ForAllValues:StringEquals" = {
            "dynamodb:Attributes" = ["PK", "SK", "accounting"]
          }
          StringEqualsIfExists = {
            "dynamodb:ReturnValues" = ["NONE", "UPDATED_OLD", "UPDATED_NEW"]
          }
        }
      },
      {
        # The tenant's own partition: which locations share a Stripe account
        # (payouts are booked on one of them).
        Sid      = "ListTenantLocations"
        Effect   = "Allow"
        Action   = "dynamodb:Query"
        Resource = var.location_table_arn
      },
      {
        Sid    = "ReadSales"
        Effect = "Allow"
        Action = ["dynamodb:Query", "dynamodb:GetItem"]
        Resource = [
          var.order_table_arn,
          var.reservation_table_arn,
          var.catering_requests_table_arn,
          var.catering_history_table_arn,
          var.kassa_table_arn,
          var.kassa_journal_table_arn,
          "${var.kassa_journal_table_arn}/index/byDay",
        ]
      },
      {
        # The platform Stripe key (Stripe-Account header = the restaurant):
        # balance transactions, read only.
        Sid      = "ReadStripeSecret"
        Effect   = "Allow"
        Action   = "secretsmanager:GetSecretValue"
        Resource = var.stripe_secret_arn
      },
    ]
  })
}

resource "aws_iam_role_policy" "logs" {
  name = "cloudwatch-logs"
  role = aws_iam_role.fn.id
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Sid      = "WriteLogs"
      Effect   = "Allow"
      Action   = ["logs:CreateLogStream", "logs:PutLogEvents"]
      Resource = "arn:aws:logs:${var.region}:${local.account}:log-group:/aws/lambda/${local.name}:*"
    }]
  })
}

resource "aws_cloudwatch_log_group" "fn" {
  name              = "/aws/lambda/${local.name}"
  retention_in_days = 30

  tags = {
    Environment = var.environment
  }
}

resource "aws_lambda_function" "fn" {
  function_name = local.name
  role          = aws_iam_role.fn.arn
  package_type  = "Image"
  image_uri     = "${var.ecr_repository_url}:latest"
  publish       = true
  architectures = ["arm64"]
  # A year's export reads a few hundred DynamoDB pages and Stripe's list.
  # API Gateway stops at 30 s.
  timeout     = 29
  memory_size = 1024

  # The application pipeline releases <repo>:<sha>; Terraform sets only the first image.
  lifecycle {
    ignore_changes = [image_uri]
  }

  environment {
    variables = {
      ENVIRONMENT                         = var.environment
      TENANT_TABLE_NAME                   = var.tenant_table_name
      LOCATION_TABLE_NAME                 = var.location_table_name
      LOCATION_ID_INDEX_NAME              = var.location_id_index_name
      USER_TABLE_NAME                     = var.user_table_name
      ORDER_TABLE_NAME                    = var.order_table_name
      RESERVATION_TABLE_NAME              = var.reservation_table_name
      CATERING_REQUESTS_TABLE_NAME        = var.catering_requests_table_name
      CATERING_REQUEST_HISTORY_TABLE_NAME = var.catering_history_table_name
      KASSA_TABLE_NAME                    = var.kassa_table_name
      KASSA_JOURNAL_TABLE_NAME            = var.kassa_journal_table_name
      STRIPE_SECRET_ARN                   = var.stripe_secret_arn
      STRIPE_API_VERSION                  = var.stripe_api_version
    }
  }

  depends_on = [aws_cloudwatch_log_group.fn, aws_iam_role_policy.logs]

  tags = {
    Environment = var.environment
  }
}

# Callers invoke "live"; CodeDeploy moves it (orchestration/lambda-releases).
resource "aws_lambda_alias" "live" {
  name             = "live"
  function_name    = aws_lambda_function.fn.function_name
  function_version = aws_lambda_function.fn.version

  lifecycle {
    ignore_changes = [function_version, routing_config]
  }
}

resource "aws_cloudwatch_metric_alarm" "errors" {
  alarm_name        = "${local.name}-errors"
  alarm_description = "accounting crashed (Lambda errors): an account mapping save or a SIE/CSV export failed. Check the accounting logs; nothing is written but the mapping."
  namespace         = "AWS/Lambda"
  metric_name       = "Errors"
  dimensions        = { FunctionName = aws_lambda_function.fn.function_name }

  statistic           = "Sum"
  period              = 300
  evaluation_periods  = 1
  comparison_operator = "GreaterThanThreshold"
  threshold           = 0
  treat_missing_data  = "notBreaching"

  alarm_actions = [var.alert_topic_arn]

  tags = {
    Environment = var.environment
  }
}
