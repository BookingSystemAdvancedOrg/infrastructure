# Events and tickets (feature K, ADR-K, CONTRACTS.md 4, 6.K, 9, 11): events with
# occurrences and ticket types, prepaid checkout on the restaurant's connected
# Stripe account, QR scanning and guest list, gift transfer, refunds and mass
# refund. Application: functions/events-tickets (JWT K1-K14, public K15-K22,
# hooks stripe.event, accounting.events, insights.events, privacy.*,
# tenant.purge, the 5-minute sweep and the nightly clean-up),
# shared/features/events_tickets.
#
# All access is on the NEW role. The callers' invoke grants on
# events-tickets:live (stripe-webhook, accounting, insights, guest-privacy,
# tenant-purge) exist since the Run 0 addendum (security/iam/feature-hooks);
# no existing role changes here. Not in this run (so no IAM for them): table
# pick (reservation tables), Wallet pass secrets, event images (menu bucket).

data "aws_caller_identity" "current" {}

locals {
  prefix        = var.environment == "prod" ? "" : "${var.environment}-"
  account       = data.aws_caller_identity.current.account_id
  name          = "${local.prefix}events-tickets"
  function_name = local.name
  table_arn     = aws_dynamodb_table.this.arn

  statements = [
    {
      # Own table only. TransactWriteItems is authorised per item (Put/Update/Delete).
      Sid      = "EventsTicketsTable"
      Effect   = "Allow"
      Action   = ["dynamodb:GetItem", "dynamodb:PutItem", "dynamodb:UpdateItem", "dynamodb:DeleteItem", "dynamodb:Query"]
      Resource = [local.table_arn, "${local.table_arn}/index/byOccurrence", "${local.table_arn}/index/byLocationDay"]
    },
    {
      # Code/scan-key/link pepper (own), platform Stripe key and Turnstile secret (read).
      Sid      = "Secrets"
      Effect   = "Allow"
      Action   = ["secretsmanager:GetSecretValue"]
      Resource = [aws_secretsmanager_secret.pepper.arn, var.stripe_secret_arn, var.turnstile_secret_arn]
    },
    {
      Sid      = "CountCheckoutAttempts"
      Effect   = "Allow"
      Action   = ["dynamodb:UpdateItem"]
      Resource = var.request_guard_table_arn
    },
    {
      Sid      = "SendTicketEmails"
      Effect   = "Allow"
      Action   = ["lambda:InvokeFunction"]
      Resource = var.notification_function_arn
    },
    {
      Sid       = "PublishEventsTicketsEvents"
      Effect    = "Allow"
      Action    = ["events:PutEvents"]
      Resource  = var.event_bus_arn
      Condition = { StringEquals = { "events:source" = "booqy.events-tickets" } }
    },
  ]
}

# --- table -------------------------------------------------------------------------------

resource "aws_dynamodb_table" "this" {
  name         = local.name
  billing_mode = "PAY_PER_REQUEST"
  hash_key     = "PK"
  range_key    = "SK"

  # TENANT#<t> / EVENT#, EVENT#<e>#OCC#, EVENT#<e>#TYPE#, ORDER#, TICKET#, CODE#, TRANSFER#, TX#, JOB#
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

  attribute {
    name = "GSI2PK"
    type = "S"
  }

  attribute {
    name = "GSI2SK"
    type = "S"
  }

  # Guest list per occurrence (TICKET rows); sparse HOLD and JOBS rows for the sweep.
  global_secondary_index {
    name            = "byOccurrence"
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

  # TX rows per location and day (Bokföring, Statistik); sparse CLEANUP#<month> order rows.
  global_secondary_index {
    name            = "byLocationDay"
    projection_type = "ALL"

    key_schema {
      attribute_name = "GSI2PK"
      key_type       = "HASH"
    }

    key_schema {
      attribute_name = "GSI2SK"
      key_type       = "RANGE"
    }
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

# --- the pepper (random, never leaves Secrets Manager) ------------------------------------

resource "random_password" "pepper" {
  length  = 48
  special = false
}

resource "aws_secretsmanager_secret" "pepper" {
  name                    = "${local.prefix}events-tickets/code-pepper"
  description             = "HMAC pepper for ticket codes, door scan keys and ticket link tokens"
  recovery_window_in_days = var.environment == "prod" ? 30 : 7

  tags = {
    Environment = var.environment
  }
}

resource "aws_secretsmanager_secret_version" "pepper" {
  secret_id     = aws_secretsmanager_secret.pepper.id
  secret_string = random_password.pepper.result
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
  name   = "events-tickets-access"
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
  timeout       = 120 # API and hooks answer in seconds; the sweep's mass refund batches use the rest
  memory_size   = 512

  lifecycle {
    ignore_changes = [image_uri]
  }

  environment {
    variables = {
      ENVIRONMENT                      = var.environment
      EVENTS_TICKETS_TABLE_NAME        = aws_dynamodb_table.this.name
      TENANT_TABLE_NAME                = var.tenant_table_name
      LOCATION_TABLE_NAME              = var.location_table_name
      LOCATION_ID_INDEX_NAME           = var.location_id_index_name
      USER_TABLE_NAME                  = var.user_table_name
      EVENTS_TICKETS_PEPPER_SECRET_ARN = aws_secretsmanager_secret.pepper.arn
      STRIPE_SECRET_ARN                = var.stripe_secret_arn
      STRIPE_API_VERSION               = var.stripe_api_version
      TURNSTILE_REQUIRED               = var.turnstile_required ? "true" : "false"
      TURNSTILE_SECRET_ARN             = var.turnstile_secret_arn
      REQUEST_GUARD_TABLE_NAME         = var.request_guard_table_name
      NOTIFICATION_FUNCTION_NAME       = var.notification_function_arn
      EVENT_BUS_NAME                   = var.event_bus_name
      CLOUDFRONT_EDGE_SECRET           = var.cloudfront_edge_secret
      SITE_DOMAIN                      = var.site_domain
      CUSTOMER_SITE_URL                = var.customer_site_url
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

# --- schedules: sweep every 5 minutes, nightly 02:45 Europe/Stockholm ---------------------------

resource "aws_scheduler_schedule_group" "this" {
  name = local.name

  tags = {
    Environment = var.environment
  }
}

resource "aws_iam_role" "scheduler" {
  name = "${local.prefix}scheduler-invoke-events-tickets-role"

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
  name = "invoke-events-tickets"
  role = aws_iam_role.scheduler.id
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Sid      = "InvokeEventsTickets"
      Effect   = "Allow"
      Action   = "lambda:InvokeFunction"
      Resource = aws_lambda_alias.live.arn
    }]
  })
}

resource "aws_scheduler_schedule" "sweep" {
  name                = "${local.name}-sweep"
  group_name          = aws_scheduler_schedule_group.this.name
  schedule_expression = "rate(5 minutes)"

  flexible_time_window {
    mode = "OFF"
  }

  target {
    arn      = aws_lambda_alias.live.arn
    role_arn = aws_iam_role.scheduler.arn
    input    = jsonencode({ job = "sweep" })

    retry_policy {
      maximum_retry_attempts       = 0 # the next sweep runs in 5 minutes
      maximum_event_age_in_seconds = 300
    }
  }
}

resource "aws_scheduler_schedule" "nightly" {
  name                         = "${local.name}-nightly"
  group_name                   = aws_scheduler_schedule_group.this.name
  schedule_expression          = "cron(45 2 * * ? *)"
  schedule_expression_timezone = "Europe/Stockholm"

  flexible_time_window {
    mode = "OFF"
  }

  target {
    arn      = aws_lambda_alias.live.arn
    role_arn = aws_iam_role.scheduler.arn
    input    = jsonencode({ job = "nightly" })

    retry_policy {
      maximum_retry_attempts       = 2
      maximum_event_age_in_seconds = 3600
    }
  }
}

# --- alarms --------------------------------------------------------------------------------

resource "aws_cloudwatch_metric_alarm" "errors" {
  alarm_name          = "${local.function_name}-errors"
  alarm_description   = "events-tickets Lambda errors"
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
