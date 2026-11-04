# Waitlist and walk-in queue (feature F, ADR-F, CONTRACTS.md 4, 6.F, 7, 9.4):
# one same-day queue per location; an offer is an existing table hold.
# Application: functions/waitlist (JWT routes F1-F6, public routes F7-F10,
# the one-time offer expiry timer, hooks privacy.export/erase, tenant.purge),
# shared/features/waitlist.
#
# All access below is on the NEW waitlist role except where called out: the
# role writes the existing reservation and slot-occupancy tables exactly
# like create-pending-reservation, and UpdateItem on the location table is
# limited to the `waitlist` attribute (CONTRACTS.md 4). The hook callers'
# invoke grants (guest-privacy, tenant-purge) exist since Run 0.

data "aws_caller_identity" "current" {}

locals {
  prefix         = var.environment == "prod" ? "" : "${var.environment}-"
  account        = data.aws_caller_identity.current.account_id
  function_name  = "${local.prefix}waitlist"
  self_alias_arn = "arn:aws:lambda:${var.region}:${local.account}:function:${local.function_name}:live"
  schedule_group = "${local.prefix}waitlist"
  table_arn      = aws_dynamodb_table.this.arn

  statements = [
    {
      Sid      = "WaitlistTable"
      Effect   = "Allow"
      Action   = ["dynamodb:GetItem", "dynamodb:PutItem", "dynamodb:UpdateItem", "dynamodb:DeleteItem", "dynamodb:Query", "dynamodb:BatchWriteItem"]
      Resource = local.table_arn
    },
    {
      # Offers are table holds: the same item actions as create-pending-reservation.
      Sid      = "HoldTables"
      Effect   = "Allow"
      Action   = ["dynamodb:BatchGetItem", "dynamodb:DeleteItem", "dynamodb:GetItem", "dynamodb:PutItem", "dynamodb:Query", "dynamodb:UpdateItem"]
      Resource = [var.slot_occupancy_table_arn, var.reservation_table_arn]
    },
    {
      Sid      = "ReadLayoutSnapshot"
      Effect   = "Allow"
      Action   = ["dynamodb:GetItem", "dynamodb:Query"]
      Resource = var.published_layout_snapshot_table_arn
    },
    {
      # Mirror of publicJoin for /site-config: the one attribute only.
      Sid       = "MirrorPublicJoin"
      Effect    = "Allow"
      Action    = ["dynamodb:UpdateItem"]
      Resource  = var.location_table_arn
      Condition = { "ForAllValues:StringEquals" = { "dynamodb:Attributes" = ["PK", "SK", "waitlist"] } }
    },
    {
      Sid      = "LinkKeyAndTurnstile"
      Effect   = "Allow"
      Action   = ["secretsmanager:GetSecretValue"]
      Resource = [var.reservation_link_key_secret_arn, var.turnstile_secret_arn]
    },
    {
      Sid      = "CountJoinAttempts"
      Effect   = "Allow"
      Action   = ["dynamodb:UpdateItem"]
      Resource = var.request_guard_table_arn
    },
    {
      Sid      = "SendSms"
      Effect   = "Allow"
      Action   = ["lambda:InvokeFunction"]
      Resource = var.notification_function_arn
    },
    {
      Sid      = "OfferTimers"
      Effect   = "Allow"
      Action   = ["scheduler:CreateSchedule", "scheduler:DeleteSchedule"]
      Resource = "arn:aws:scheduler:${var.region}:${local.account}:schedule/${local.schedule_group}/*"
    },
    {
      Sid       = "PassSchedulerRole"
      Effect    = "Allow"
      Action    = ["iam:PassRole"]
      Resource  = aws_iam_role.scheduler.arn
      Condition = { StringEquals = { "iam:PassedToService" = "scheduler.amazonaws.com" } }
    },
    {
      Sid       = "PublishWaitlistEvents"
      Effect    = "Allow"
      Action    = ["events:PutEvents"]
      Resource  = var.event_bus_arn
      Condition = { StringEquals = { "events:source" = "booqy.waitlist" } }
    },
  ]
}

# --- table -------------------------------------------------------------------------------

resource "aws_dynamodb_table" "this" {
  name         = local.function_name
  billing_mode = "PAY_PER_REQUEST"
  hash_key     = "PK"
  range_key    = "SK"

  # LOCATION#<l> / ENTRY#<day>#<entryId>, SETTINGS (CONTRACTS.md 4); no stream:
  # SMS go through a direct notification invoke.
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
  name   = "waitlist-access"
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
      ENVIRONMENT                          = var.environment
      WAITLIST_TABLE_NAME                  = aws_dynamodb_table.this.name
      TENANT_TABLE_NAME                    = var.tenant_table_name
      LOCATION_TABLE_NAME                  = var.location_table_name
      LOCATION_ID_INDEX_NAME               = var.location_id_index_name
      USER_TABLE_NAME                      = var.user_table_name
      RESERVATION_TABLE_NAME               = var.reservation_table_name
      SLOT_OCCUPANCY_TABLE_NAME            = var.slot_occupancy_table_name
      PUBLISHED_LAYOUT_SNAPSHOT_TABLE_NAME = var.published_layout_snapshot_table_name
      RESERVATION_LINK_KEY_SECRET_ARN      = var.reservation_link_key_secret_arn
      RESERVATION_RETENTION_DAYS           = tostring(var.reservation_retention_days)
      TURNSTILE_REQUIRED                   = var.turnstile_required ? "true" : "false"
      TURNSTILE_SECRET_ARN                 = var.turnstile_secret_arn
      REQUEST_GUARD_TABLE_NAME             = var.request_guard_table_name
      NOTIFICATION_FUNCTION_NAME           = var.notification_function_arn
      EVENT_BUS_NAME                       = var.event_bus_name
      SCHEDULE_GROUP_NAME                  = local.schedule_group
      SCHEDULER_INVOKE_ROLE_ARN            = aws_iam_role.scheduler.arn
      SELF_FUNCTION_ARN                    = local.self_alias_arn
      SITE_DOMAIN                          = var.site_domain
      CUSTOMER_SITE_URL                    = var.customer_site_url
      CLOUDFRONT_EDGE_SECRET               = var.cloudfront_edge_secret
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

# --- offer expiry timers -------------------------------------------------------------------

resource "aws_scheduler_schedule_group" "offers" {
  name = local.schedule_group

  tags = {
    Environment = var.environment
  }
}

resource "aws_iam_role" "scheduler" {
  name = "${local.prefix}scheduler-invoke-waitlist-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect    = "Allow"
      Principal = { Service = "scheduler.amazonaws.com" }
      Action    = "sts:AssumeRole"
      Condition = { StringEquals = { "aws:SourceAccount" = local.account } }
    }]
  })

  tags = {
    Environment = var.environment
  }
}

resource "aws_iam_role_policy" "scheduler" {
  name = "invoke-waitlist"
  role = aws_iam_role.scheduler.id
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Sid      = "InvokeWaitlist"
      Effect   = "Allow"
      Action   = "lambda:InvokeFunction"
      Resource = aws_lambda_alias.live.arn
    }]
  })
}

# --- alarms --------------------------------------------------------------------------------

resource "aws_cloudwatch_metric_alarm" "errors" {
  alarm_name          = "${local.function_name}-errors"
  alarm_description   = "waitlist Lambda errors"
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
