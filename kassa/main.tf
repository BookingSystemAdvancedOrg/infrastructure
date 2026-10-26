# Kassa, the till in the admin app (feature "kassa", off by default), built
# for Skatteverket's cash register rules: application/docs/KASSA-REQUIREMENTS.md.
# Application side: functions/kassa, shared/kassa.py, shared/control_system.py,
# shared/kassa_xml.py, shared/kassa_receipt.py.
#
# Everything the feature owns lives in this module except the ECR repository
# (config.tf, CI bootstraps images from it) and the API routes
# (network/api-gateway/kassa-routes.tf). Card payments reuse the
# terminal-payments records in the order table; prints go to the print
# table; e-mailed receipts are order-table notices the notification
# function sends.
#
#   kassa          registers, open bills, receipt pointers (mutable)
#   kassa-journal  the journal memory: append-only, kept at least 7 years
#                  (Bokföringslagen); no TTL, no role may update or delete

data "aws_caller_identity" "current" {}

locals {
  prefix   = var.environment == "prod" ? "" : "${var.environment}-"
  account  = data.aws_caller_identity.current.account_id
  function = "kassa"
  name     = "${local.prefix}${local.function}"
  # One secret per restaurant with its fiskaly API key (shared/control_system_fiskaly.py).
  fiskaly_unit_prefix = "booqy/${var.environment}/fiskaly-unit/"
}

# --- tables --------------------------------------------------------------------------

# PK LOCATION#<locationId>; SK REGISTER#<id> | BILL#<id> | RCPT#<registerId>#<seq>.
# Closed and voided bills expire (ttl) after 90 days; registers and receipt
# pointers have no ttl.
resource "aws_dynamodb_table" "kassa" {
  name         = local.name
  billing_mode = "PAY_PER_REQUEST"
  hash_key     = "PK"
  range_key    = "SK"

  attribute {
    name = "PK"
    type = "S"
  }

  attribute {
    name = "SK"
    type = "S"
  }

  ttl {
    attribute_name = "ttl"
    enabled        = true
  }

  point_in_time_recovery {
    enabled = true
  }

  server_side_encryption {
    enabled = true
  }

  deletion_protection_enabled = var.environment == "prod"

  tags = {
    Environment = var.environment
  }
}

# PK REG#<registerId>, SK J#<12-digit journal sequence>: one item per
# registration (receipt, return, copy, training receipt, X/Z report, float,
# mode change, control system status, removed line), each with the SHA-256
# of the one before. byDay (regDay = REG#<registerId>#<local date>) serves
# the day's list and the XML export by period.
resource "aws_dynamodb_table" "journal" {
  name         = "${local.name}-journal"
  billing_mode = "PAY_PER_REQUEST"
  hash_key     = "PK"
  range_key    = "SK"

  attribute {
    name = "PK"
    type = "S"
  }

  attribute {
    name = "SK"
    type = "S"
  }

  attribute {
    name = "regDay"
    type = "S"
  }

  global_secondary_index {
    name            = "byDay"
    projection_type = "ALL"

    key_schema {
      attribute_name = "regDay"
      key_type       = "HASH"
    }

    key_schema {
      attribute_name = "SK"
      key_type       = "RANGE"
    }
  }

  # No TTL: the journal is bookkeeping material, kept at least 7 years after
  # the end of the calendar year (BFL 7 kap. 2 §). data-retention and
  # tenant-purge have no access to this table.

  point_in_time_recovery {
    enabled = true
  }

  server_side_encryption {
    enabled = true
  }

  # Prod: dropping the table would destroy the journal memory.
  deletion_protection_enabled = var.environment == "prod"

  tags = {
    Environment = var.environment
  }
}

# On top of IAM (the kassa role has only PutItem/GetItem/Query here): an
# explicit Deny for every principal, so nothing can change or delete a
# registration (SKVFS 2014:9 6 kap. 1 §). Appending stays allowed. Removing
# this policy is itself a deliberate, logged act. Same pattern as the
# catering request history.
resource "aws_dynamodb_resource_policy" "journal_append_only" {
  resource_arn = aws_dynamodb_table.journal.arn

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid       = "DenyJournalMutation"
        Effect    = "Deny"
        Principal = "*"
        Action = [
          "dynamodb:UpdateItem",
          "dynamodb:DeleteItem",
          "dynamodb:BatchWriteItem",
          "dynamodb:PartiQLUpdate",
          "dynamodb:PartiQLDelete",
        ]
        Resource = aws_dynamodb_table.journal.arn
      }
    ]
  })
}

# --- function --------------------------------------------------------------------------

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

# Least privilege. Tenant/location reads and the staff location check come
# from the shared tenant-context policy (config.tf tenant_aware_role_names,
# staff_check_role_names). Item-level actions only: no Scan, no table-level
# actions, no DeleteItem anywhere.
resource "aws_iam_role_policy" "fn" {
  name = "${local.function}-access"
  role = aws_iam_role.fn.id
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid      = "KassaState"
        Effect   = "Allow"
        Action   = ["dynamodb:GetItem", "dynamodb:PutItem", "dynamodb:UpdateItem", "dynamodb:Query"]
        Resource = aws_dynamodb_table.kassa.arn
      },
      {
        # Append and read only.
        Sid      = "JournalAppendRead"
        Effect   = "Allow"
        Action   = ["dynamodb:PutItem", "dynamodb:GetItem", "dynamodb:Query"]
        Resource = [aws_dynamodb_table.journal.arn, "${aws_dynamodb_table.journal.arn}/index/byDay"]
      },
      {
        # Prices are read from the menu when a line is added.
        Sid      = "ReadMenu"
        Effect   = "Allow"
        Action   = ["dynamodb:GetItem", "dynamodb:BatchGetItem"]
        Resource = var.menu_table_arn
      },
      {
        # Card payment records (CARD#, CID#) of the bill, and the receipt
        # e-mail notices (KASSAMAIL#, expire after a day).
        Sid      = "CardPaymentsAndReceiptMail"
        Effect   = "Allow"
        Action   = ["dynamodb:GetItem", "dynamodb:PutItem", "dynamodb:UpdateItem", "dynamodb:Query"]
        Resource = var.order_table_arn
      },
      {
        # Printer settings and Kassa print jobs.
        Sid      = "PrintJobs"
        Effect   = "Allow"
        Action   = ["dynamodb:GetItem", "dynamodb:PutItem"]
        Resource = var.print_table_arn
      },
      {
        # The platform Stripe key (Stripe-Account header = the restaurant).
        Sid      = "ReadStripeSecret"
        Effect   = "Allow"
        Action   = "secretsmanager:GetSecretValue"
        Resource = var.stripe_secret_arn
      },
    ]
  })
}

# fiskaly SIGN SE (the certified control system): read only its own key, the
# one secret, created by hand (never by Terraform, so no value is in state).
# "-??????" is the random suffix Secrets Manager adds to a secret's ARN.
resource "aws_iam_role_policy" "fiskaly" {
  count = var.fiskaly_secret_name == "" ? 0 : 1
  name  = "${local.function}-fiskaly-secret"
  role  = aws_iam_role.fn.id
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Sid      = "ReadFiskalySecret"
      Effect   = "Allow"
      Action   = "secretsmanager:GetSecretValue"
      Resource = "arn:aws:secretsmanager:${var.region}:${local.account}:secret:${var.fiskaly_secret_name}-??????"
    }]
  })
}

# Each restaurant (fiskaly UNIT) has its own fiskaly API key, created by
# the kassa function when the restaurant's first register is enrolled and
# kept in one secret per tenant: booqy/<env>/fiskaly-unit/<tenantId>.
# Create, read and update only; tenant-purge deletes it at offboarding.
resource "aws_iam_role_policy" "fiskaly_units" {
  count = var.fiskaly_secret_name == "" ? 0 : 1
  name  = "${local.function}-fiskaly-unit-keys"
  role  = aws_iam_role.fn.id
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Sid      = "FiskalyUnitKeys"
      Effect   = "Allow"
      Action   = ["secretsmanager:CreateSecret", "secretsmanager:GetSecretValue", "secretsmanager:PutSecretValue"]
      Resource = "arn:aws:secretsmanager:${var.region}:${local.account}:secret:${local.fiskaly_unit_prefix}*"
    }]
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
  # A receipt is a lock, the control system and one transaction; a return
  # also refunds on Stripe. API Gateway stops at 30 s.
  timeout     = 29
  memory_size = 512

  # The application pipeline releases <repo>:<sha>; Terraform sets only the first image.
  lifecycle {
    ignore_changes = [image_uri]
  }

  environment {
    variables = {
      ENVIRONMENT              = var.environment
      TENANT_TABLE_NAME        = var.tenant_table_name
      LOCATION_TABLE_NAME      = var.location_table_name
      LOCATION_ID_INDEX_NAME   = var.location_id_index_name
      USER_TABLE_NAME          = var.user_table_name
      KASSA_TABLE_NAME         = aws_dynamodb_table.kassa.name
      KASSA_JOURNAL_TABLE_NAME = aws_dynamodb_table.journal.name
      MENU_TABLE_NAME          = var.menu_table_name
      ORDER_TABLE_NAME         = var.order_table_name
      PRINT_TABLE_NAME         = var.print_table_name
      STRIPE_SECRET_ARN        = var.stripe_secret_arn
      STRIPE_API_VERSION       = var.stripe_api_version
      # "true" only with a certified control system connected; the simulator
      # ignores it. Until then every screen and receipt says "Testläge".
      KASSA_CERTIFIED = var.certified ? "true" : "false"
      # simulator or fiskaly; fiskaly reads its key from FISKALY_SECRET_ID.
      KASSA_CONTROL_SYSTEM = var.control_system
      FISKALY_SECRET_ID    = var.fiskaly_secret_name
      FISKALY_UNIT_PREFIX  = local.fiskaly_unit_prefix
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
  alarm_description = "kassa crashed (Lambda errors): a sale, return, copy or report at the till failed. Check the kassa logs; the journal is unchanged by a failed request."
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
