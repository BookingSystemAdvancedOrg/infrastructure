# Gift cards (feature E, ADR-E, CONTRACTS.md 4, 6.E, 9, 11): sold on the
# restaurant site, issued from Stripe only, redeemed online, booked
# in Bokföring (multi-purpose voucher: NEEDS ACCOUNTANT REVIEW). Application:
# functions/gift-cards (public E1-E3, JWT E4-E11, hooks stripe.event,
# checkout.giftcard, accounting.events, privacy.*,
# tenant.purge, the nightly expiry), shared/features/gift_cards.
#
# All access is on the NEW role. The callers' invoke grants on
# gift-cards:live (stripe-webhook, payment-intent, webhook-payment-intent,
# manage-order, accounting, guest-privacy, tenant-purge) exist since
# Run 0 (security/iam/feature-hooks); no existing role changes here. Kassa
# redemption (E12, E13, the kassa.giftcard hook) went with Kassa on 2026-11-14.

data "aws_caller_identity" "current" {}

locals {
  prefix        = var.environment == "prod" ? "" : "${var.environment}-"
  account       = data.aws_caller_identity.current.account_id
  function_name = "${local.prefix}gift-cards"
  table_arn     = aws_dynamodb_table.this.arn

  statements = [
    {
      Sid      = "GiftCardsTable"
      Effect   = "Allow"
      Action   = ["dynamodb:GetItem", "dynamodb:PutItem", "dynamodb:UpdateItem", "dynamodb:DeleteItem", "dynamodb:Query"]
      Resource = [local.table_arn, "${local.table_arn}/index/byLocationDay", "${local.table_arn}/index/byExpiry"]
    },
    {
      # Code HMAC pepper (own), platform Stripe key and Turnstile secret (read).
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
      Sid      = "SendCodeEmail"
      Effect   = "Allow"
      Action   = ["lambda:InvokeFunction"]
      Resource = var.notification_function_arn
    },
    {
      Sid       = "PublishGiftCardEvents"
      Effect    = "Allow"
      Action    = ["events:PutEvents"]
      Resource  = var.event_bus_arn
      Condition = { StringEquals = { "events:source" = "booqy.gift-cards" } }
    },
  ]
}

# --- table -------------------------------------------------------------------------------

resource "aws_dynamodb_table" "this" {
  name         = local.function_name
  billing_mode = "PAY_PER_REQUEST"
  hash_key     = "PK"
  range_key    = "SK"

  # TENANT#<t> / SETTINGS, PURCHASE#, CARD#, CODE#, CARD#<c>#TX#<tx>, TXREF#<tx>; JOB / NIGHTLY
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

  # TX rows per location and day, for Bokföring (accounting.events).
  global_secondary_index {
    name            = "byLocationDay"
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

  # Sparse: active cards by expiry day, and finished cards by contact clean-up day.
  global_secondary_index {
    name            = "byExpiry"
    projection_type = "KEYS_ONLY"

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

# --- the code pepper (random, never leaves Secrets Manager) --------------------------------

resource "random_password" "pepper" {
  length  = 48
  special = false
}

resource "aws_secretsmanager_secret" "pepper" {
  name                    = "${local.prefix}gift-cards/code-pepper"
  description             = "HMAC pepper for gift card codes (codes are stored only as HMAC + last 4)"
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
  name   = "gift-cards-access"
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
  timeout       = 120 # API and hooks answer in seconds; the nightly job uses the rest
  memory_size   = 512

  lifecycle {
    ignore_changes = [image_uri]
  }

  environment {
    variables = {
      ENVIRONMENT                 = var.environment
      GIFT_CARDS_TABLE_NAME       = aws_dynamodb_table.this.name
      TENANT_TABLE_NAME           = var.tenant_table_name
      LOCATION_TABLE_NAME         = var.location_table_name
      LOCATION_ID_INDEX_NAME      = var.location_id_index_name
      USER_TABLE_NAME             = var.user_table_name
      GIFT_CARD_PEPPER_SECRET_ARN = aws_secretsmanager_secret.pepper.arn
      STRIPE_SECRET_ARN           = var.stripe_secret_arn
      STRIPE_API_VERSION          = var.stripe_api_version
      TURNSTILE_REQUIRED          = var.turnstile_required ? "true" : "false"
      TURNSTILE_SECRET_ARN        = var.turnstile_secret_arn
      REQUEST_GUARD_TABLE_NAME    = var.request_guard_table_name
      NOTIFICATION_FUNCTION_NAME  = var.notification_function_arn
      EVENT_BUS_NAME              = var.event_bus_name
      CLOUDFRONT_EDGE_SECRET      = var.cloudfront_edge_secret
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

# --- nightly expiry (02:30 Europe/Stockholm) ------------------------------------------------

resource "aws_iam_role" "scheduler" {
  name = "${local.prefix}scheduler-invoke-gift-cards-role"

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
  name = "invoke-gift-cards"
  role = aws_iam_role.scheduler.id
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Sid      = "InvokeGiftCards"
      Effect   = "Allow"
      Action   = "lambda:InvokeFunction"
      Resource = aws_lambda_alias.live.arn
    }]
  })
}

resource "aws_scheduler_schedule" "nightly" {
  name                         = "${local.prefix}gift-cards-nightly"
  group_name                   = "default"
  schedule_expression          = "cron(30 2 * * ? *)"
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
  alarm_description   = "gift-cards Lambda errors"
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
