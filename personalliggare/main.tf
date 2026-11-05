# Personalliggare, the electronic staff ledger (feature H, ADR-H, CONTRACTS.md
# 4, 5, 6.H, 9). NEEDS LEGAL REVIEW before any tenant uses it; the
# entitlement `personalliggare` is false in every plan.
# Application: functions/personalliggare (JWT routes H1-H8, hooks platform
# (H9 export) and tenant.purge), shared/features/personalliggare.
#
# Two tables, the kassa journal pattern: a mutable state table and an
# append-only ledger with an explicit Deny resource policy on Update/Delete.
# All access below is on the NEW personalliggare role; no existing role is
# changed here (the hook callers' invoke grants on personalliggare:live,
# platform-tenants and tenant-purge, exist since Run 0, CONTRACTS.md 14 row
# 2 and 10). Tenant, location and user reads come from the shared
# tenant-context and staff-check policies (wiring output).

data "aws_caller_identity" "current" {}

locals {
  prefix        = var.environment == "prod" ? "" : "${var.environment}-"
  account       = data.aws_caller_identity.current.account_id
  function_name = "${local.prefix}personalliggare"

  statements = [
    {
      # Persons, user pointers, the chain HEAD, presence and idempotency
      # markers; BatchWriteItem only for the tenant.purge hook.
      Sid      = "StateTable"
      Effect   = "Allow"
      Action   = ["dynamodb:GetItem", "dynamodb:PutItem", "dynamodb:UpdateItem", "dynamodb:DeleteItem", "dynamodb:Query", "dynamodb:BatchWriteItem"]
      Resource = aws_dynamodb_table.state.arn
    },
    {
      # Append and read only: no UpdateItem, DeleteItem or BatchWriteItem
      # (the resource policy denies them to everyone anyway).
      Sid      = "LedgerAppendAndRead"
      Effect   = "Allow"
      Action   = ["dynamodb:PutItem", "dynamodb:GetItem", "dynamodb:Query"]
      Resource = [aws_dynamodb_table.ledger.arn, "${aws_dynamodb_table.ledger.arn}/index/byDay"]
    },
    {
      Sid       = "PublishLedgerEvents"
      Effect    = "Allow"
      Action    = ["events:PutEvents"]
      Resource  = var.event_bus_arn
      Condition = { StringEquals = { "events:source" = "booqy.personalliggare" } }
    },
  ]
}

# --- tables ------------------------------------------------------------------------------

resource "aws_dynamodb_table" "state" {
  name         = local.function_name
  billing_mode = "PAY_PER_REQUEST"
  hash_key     = "PK"
  range_key    = "SK"

  # TENANT#<t> / PERSON#<id>, USER#<sub>; LOCATION#<l> / HEAD, PRESENT#<personId>,
  # REQ#<recordId> (CONTRACTS.md 4). Purged on offboarding (tenant.purge hook).
  attribute {
    name = "PK"
    type = "S"
  }

  attribute {
    name = "SK"
    type = "S"
  }

  ttl {
    attribute_name = "ttl" # REQ# idempotency markers, 7 days
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

resource "aws_dynamodb_table" "ledger" {
  name         = "${local.function_name}-ledger"
  billing_mode = "PAY_PER_REQUEST"
  hash_key     = "PK"
  range_key    = "SK"

  # LOCATION#<l> / SEQ#<12-digit seq>; byDay: DAY#<l>#<local day> / SEQ#...
  attribute {
    name = "PK"
    type = "S"
  }

  attribute {
    name = "SK"
    type = "S"
  }

  attribute {
    name = "GSI1PK"
    type = "S"
  }

  attribute {
    name = "GSI1SK"
    type = "S"
  }

  global_secondary_index {
    name            = "byDay"
    projection_type = "ALL"

    key_schema {
      attribute_name = "GSI1PK"
      key_type       = "HASH"
    }

    key_schema {
      attribute_name = "GSI1SK"
      key_type       = "RANGE"
    }
  }

  # Each record expires at the end of the 2nd calendar year after it (ADR-H
  # 7, legal to confirm). UNVERIFIED: that the Deny resource policy below does
  # not stop TTL deletes (TTL runs as the DynamoDB service); see STATUS.md.
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

  # Every environment (CONTRACTS.md 4): dropping the table would destroy the ledger.
  deletion_protection_enabled = true

  tags = {
    Environment = var.environment
  }
}

# On top of IAM (the role has only PutItem/GetItem/Query on the ledger): an
# explicit Deny for every principal, so nothing can change or delete a
# record. Appending stays allowed. Same shape as kassa's journal_append_only;
# removing this policy is itself a deliberate, logged act.
resource "aws_dynamodb_resource_policy" "ledger_append_only" {
  resource_arn = aws_dynamodb_table.ledger.arn

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid       = "DenyLedgerMutation"
        Effect    = "Deny"
        Principal = "*"
        Action = [
          "dynamodb:UpdateItem",
          "dynamodb:DeleteItem",
          "dynamodb:BatchWriteItem",
          "dynamodb:PartiQLUpdate",
          "dynamodb:PartiQLDelete",
        ]
        Resource = aws_dynamodb_table.ledger.arn
      }
    ]
  })
}

# --- function ----------------------------------------------------------------------------

resource "aws_iam_role" "fn" {
  name = "${local.function_name}-role"

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

resource "aws_iam_role_policy" "fn" {
  name   = "personalliggare-access"
  role   = aws_iam_role.fn.id
  policy = jsonencode({ Version = "2012-10-17", Statement = local.statements })
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
      Resource = "arn:aws:logs:${var.region}:${local.account}:log-group:/aws/lambda/${local.function_name}:*"
    }]
  })
}

resource "aws_cloudwatch_log_group" "fn" {
  name              = "/aws/lambda/${local.function_name}"
  retention_in_days = 30

  tags = {
    Environment = var.environment
  }
}

resource "aws_lambda_function" "fn" {
  function_name = local.function_name
  role          = aws_iam_role.fn.arn
  package_type  = "Image"
  image_uri     = "${var.ecr_repository_url}:latest"
  publish       = true
  architectures = ["arm64"]
  timeout       = 28
  memory_size   = 512

  lifecycle {
    ignore_changes = [image_uri]
  }

  environment {
    variables = {
      ENVIRONMENT            = var.environment
      STATE_TABLE_NAME       = aws_dynamodb_table.state.name
      LEDGER_TABLE_NAME      = aws_dynamodb_table.ledger.name
      TENANT_TABLE_NAME      = var.tenant_table_name
      LOCATION_TABLE_NAME    = var.location_table_name
      LOCATION_ID_INDEX_NAME = var.location_id_index_name
      USER_TABLE_NAME        = var.user_table_name
      EVENT_BUS_NAME         = var.event_bus_name
    }
  }

  depends_on = [aws_cloudwatch_log_group.fn, aws_iam_role_policy.logs]

  tags = {
    Environment = var.environment
  }
}

resource "aws_lambda_alias" "live" {
  name             = "live"
  function_name    = aws_lambda_function.fn.function_name
  function_version = aws_lambda_function.fn.version

  lifecycle {
    ignore_changes = [function_version, routing_config]
  }
}

# --- alarms ------------------------------------------------------------------------------

resource "aws_cloudwatch_metric_alarm" "errors" {
  alarm_name          = "${local.function_name}-errors"
  alarm_description   = "personalliggare Lambda errors"
  namespace           = "AWS/Lambda"
  metric_name         = "Errors"
  dimensions          = { FunctionName = aws_lambda_function.fn.function_name }
  statistic           = "Sum"
  period              = 300
  evaluation_periods  = 1
  threshold           = 1
  comparison_operator = "GreaterThanOrEqualToThreshold"
  treat_missing_data  = "notBreaching"
  alarm_actions       = [var.alert_topic_arn]

  tags = {
    Environment = var.environment
  }
}
