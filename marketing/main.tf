# Marketing for restaurants (plan feature "marketing"): cookieless visit
# statistics, campaign attribution and email campaigns to guests who opted in.
# Application side: application repo, functions/marketing*, shared/marketing.py
# (data layout and privacy model), docs in docs/LAMBDA_REFERENCE.md.
#
# Everything the feature owns lives in this module: its table, its link key,
# the four functions and their roles, the send schedule, the stream mappings
# and the SES configuration set whose bounce/complaint events suppress
# addresses. ECR repositories are separate top-level modules (CI bootstraps
# images from them), API Gateway routes are in network/api-gateway.
#
#   marketing          owner API (JWT)                 ANY /marketing/{proxy+}
#   marketing-public   visits, click redirect, unsub   POST /t, GET /m/c/{token}, GET|POST /m/u/{token}
#   marketing-send     sends due campaigns              Scheduler, every 2 minutes, concurrency 1
#   marketing-sync     bookings/orders/SES -> stats     reservation + order streams, EventBridge (SES)

data "aws_caller_identity" "current" {}

locals {
  prefix   = var.environment == "prod" ? "" : "${var.environment}-"
  account  = data.aws_caller_identity.current.account_id
  config   = "${local.prefix}marketing"
  ses_from = [var.from_address, "*<${var.from_address}>"]

  common_env = {
    ENVIRONMENT            = var.environment
    TENANT_TABLE_NAME      = var.tenant_table_name
    LOCATION_TABLE_NAME    = var.location_table_name
    LOCATION_ID_INDEX_NAME = var.location_id_index_name
    MARKETING_TABLE_NAME   = aws_dynamodb_table.marketing.name
  }

  functions = {
    marketing = {
      timeout     = 28
      memory      = 512
      concurrency = -1
      env = merge(local.common_env, {
        MENU_TABLE_NAME             = var.menu_table_name
        MENU_IMAGE_BASE_URL         = var.menu_image_base_url
        CUSTOMER_SITE_URL           = var.customer_site_url
        USER_TABLE_NAME             = var.user_table_name
        NO_REPLY_EMAIL_ADDRESS      = var.from_address
        MARKETING_CONFIGURATION_SET = aws_sesv2_configuration_set.marketing.configuration_set_name
        MARKETING_MONTHLY_LIMIT     = tostring(var.monthly_email_limit)
        MAIL_OUTBOX_BUCKET_NAME     = var.mail_outbox_bucket_name
      })
    }
    marketing-public = {
      timeout     = 10
      memory      = 256
      concurrency = -1
      env = merge(local.common_env, {
        MARKETING_LINK_KEY_SECRET_ARN = aws_secretsmanager_secret.link_key.arn
      })
    }
    marketing-send = {
      timeout     = 300
      memory      = 512
      concurrency = 1 # never two runs at once
      env = merge(local.common_env, {
        MARKETING_LINK_KEY_SECRET_ARN = aws_secretsmanager_secret.link_key.arn
        MARKETING_LINK_BASE           = "${var.admin_app_url}/api"
        NO_REPLY_EMAIL_ADDRESS        = var.from_address
        MARKETING_CONFIGURATION_SET   = aws_sesv2_configuration_set.marketing.configuration_set_name
        MARKETING_MONTHLY_LIMIT       = tostring(var.monthly_email_limit)
        MARKETING_SEND_RATE           = tostring(var.send_rate)
        MAIL_OUTBOX_BUCKET_NAME       = var.mail_outbox_bucket_name
      })
    }
    marketing-sync = {
      timeout     = 60
      memory      = 256
      concurrency = -1
      env = merge(local.common_env, {
        RESERVATION_TABLE_NAME = var.reservation_table_name
        ORDER_TABLE_NAME       = var.order_table_name
      })
    }
  }

  table_arn = aws_dynamodb_table.marketing.arn

  # Least privilege per function. Tenant/location reads come from the shared
  # tenant-context policy (config.tf tenant_aware_role_names).
  statements = {
    marketing = concat([
      {
        Sid      = "MarketingTable"
        Effect   = "Allow"
        Action   = ["dynamodb:GetItem", "dynamodb:PutItem", "dynamodb:UpdateItem", "dynamodb:DeleteItem", "dynamodb:Query"]
        Resource = local.table_arn
      },
      {
        Sid      = "ReadMenuForDishBlocks"
        Effect   = "Allow"
        Action   = ["dynamodb:GetItem"]
        Resource = var.menu_table_arn
      },
      {
        # Test emails go to the signed-in owner only: their own profile.
        Sid      = "ReadOwnUserProfile"
        Effect   = "Allow"
        Action   = ["dynamodb:GetItem"]
        Resource = var.user_table_arn
      },
    ], local.ses_statements, local.outbox_statements)

    marketing-public = [
      {
        Sid      = "MarketingTable"
        Effect   = "Allow"
        Action   = ["dynamodb:GetItem", "dynamodb:UpdateItem"]
        Resource = local.table_arn
      },
      {
        Sid      = "LinkKey"
        Effect   = "Allow"
        Action   = ["secretsmanager:GetSecretValue"]
        Resource = aws_secretsmanager_secret.link_key.arn
      },
    ]

    marketing-send = concat([
      {
        Sid      = "MarketingTable"
        Effect   = "Allow"
        Action   = ["dynamodb:GetItem", "dynamodb:PutItem", "dynamodb:UpdateItem", "dynamodb:DeleteItem", "dynamodb:Query"]
        Resource = local.table_arn
      },
      {
        Sid      = "LinkKey"
        Effect   = "Allow"
        Action   = ["secretsmanager:GetSecretValue"]
        Resource = aws_secretsmanager_secret.link_key.arn
      },
    ], local.ses_statements, local.outbox_statements)

    marketing-sync = [
      {
        Sid      = "MarketingTable"
        Effect   = "Allow"
        Action   = ["dynamodb:GetItem", "dynamodb:PutItem", "dynamodb:UpdateItem"]
        Resource = local.table_arn
      },
      {
        Sid      = "ReadBookingAndOrderStreams"
        Effect   = "Allow"
        Action   = ["dynamodb:DescribeStream", "dynamodb:GetRecords", "dynamodb:GetShardIterator", "dynamodb:ListStreams"]
        Resource = [var.reservation_stream_arn, var.order_stream_arn]
      },
    ]
  }

  ses_statements = [
    {
      Sid      = "SendFromNoReplyIdentity"
      Effect   = "Allow"
      Action   = ["ses:SendRawEmail"]
      Resource = [var.ses_identity_arn, aws_sesv2_configuration_set.marketing.arn]
    },
    {
      # Sandbox: recipients are verified identities too. Only FROM no-reply.
      Sid       = "SendToVerifiedRecipientIdentities"
      Effect    = "Allow"
      Action    = ["ses:SendRawEmail"]
      Resource  = "arn:aws:ses:${var.region}:${local.account}:identity/*"
      Condition = { StringLike = { "ses:FromAddress" = local.ses_from } }
    },
  ]

  outbox_statements = var.mail_outbox_bucket_arn == "" ? [] : [
    {
      Sid      = "WriteDevMailOutbox"
      Effect   = "Allow"
      Action   = ["s3:PutObject"]
      Resource = "${var.mail_outbox_bucket_arn}/outbox/*"
    },
  ]
}

# --- table ---------------------------------------------------------------------------------

resource "aws_dynamodb_table" "marketing" {
  name         = "${local.prefix}marketing"
  billing_mode = "PAY_PER_REQUEST"
  hash_key     = "PK"
  range_key    = "SK"

  # Layout (application shared/marketing.py): TENANT#<t>#STATS / #SUB /
  # #TPL / #CMP / #USAGE partitions, CMP#<t>#<id> recipients, MSG#<id> SES
  # lookups (TTL), SCHEDULE due campaigns.
  attribute {
    name = "PK"
    type = "S"
  }

  attribute {
    name = "SK"
    type = "S"
  }

  # Recipient rows and SES message lookups expire 45 days after sending.
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

# --- link key -------------------------------------------------------------------------------

# HMAC key behind unsubscribe and click links in marketing emails.
resource "aws_secretsmanager_secret" "link_key" {
  name                    = "${local.prefix}marketing/link-key"
  description             = "HMAC key for marketing email links (unsubscribe, click)"
  recovery_window_in_days = var.environment == "prod" ? 30 : 7

  tags = {
    Environment = var.environment
  }
}

ephemeral "aws_secretsmanager_random_password" "link_key" {
  password_length     = 64
  exclude_punctuation = true
}

resource "aws_secretsmanager_secret_version" "link_key" {
  secret_id                = aws_secretsmanager_secret.link_key.id
  secret_string_wo         = ephemeral.aws_secretsmanager_random_password.link_key.random_password
  secret_string_wo_version = 1 # bump to rotate - links in already sent emails stop working
}

# --- functions ------------------------------------------------------------------------------

resource "aws_iam_role" "fn" {
  for_each = local.functions
  name     = "${local.prefix}${each.key}-role"

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
  for_each = local.functions
  name     = "${each.key}-access"
  role     = aws_iam_role.fn[each.key].id
  policy   = jsonencode({ Version = "2012-10-17", Statement = local.statements[each.key] })
}

resource "aws_iam_role_policy" "logs" {
  for_each = local.functions
  name     = "cloudwatch-logs"
  role     = aws_iam_role.fn[each.key].id
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Sid      = "WriteLogs"
      Effect   = "Allow"
      Action   = ["logs:CreateLogStream", "logs:PutLogEvents"]
      Resource = "arn:aws:logs:${var.region}:${local.account}:log-group:/aws/lambda/${local.prefix}${each.key}:*"
    }]
  })
}

resource "aws_cloudwatch_log_group" "fn" {
  for_each          = local.functions
  name              = "/aws/lambda/${local.prefix}${each.key}"
  retention_in_days = 30

  tags = {
    Environment = var.environment
  }
}

resource "aws_lambda_function" "fn" {
  for_each = local.functions

  function_name = "${local.prefix}${each.key}"
  role          = aws_iam_role.fn[each.key].arn
  package_type  = "Image"
  image_uri     = "${var.ecr_repository_urls[each.key]}:latest"
  publish       = true
  architectures = ["arm64"]
  timeout       = each.value.timeout
  memory_size   = each.value.memory

  reserved_concurrent_executions = each.value.concurrency

  # The application pipeline releases <repo>:<sha>; Terraform sets only the first image.
  lifecycle {
    ignore_changes = [image_uri]
  }

  environment {
    variables = each.value.env
  }

  depends_on = [aws_cloudwatch_log_group.fn, aws_iam_role_policy.logs]

  tags = {
    Environment = var.environment
  }
}

# Callers invoke "live"; CodeDeploy moves it (orchestration/lambda-releases).
resource "aws_lambda_alias" "live" {
  for_each         = local.functions
  name             = "live"
  function_name    = aws_lambda_function.fn[each.key].function_name
  function_version = aws_lambda_function.fn[each.key].version

  lifecycle {
    ignore_changes = [function_version, routing_config]
  }
}

# --- marketing-send: every 2 minutes ---------------------------------------------------------

resource "aws_iam_role" "scheduler" {
  name = "${local.prefix}scheduler-invoke-marketing-send-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect    = "Allow"
      Principal = { Service = "scheduler.amazonaws.com" }
      Action    = "sts:AssumeRole"
    }]
  })

  tags = {
    Environment = var.environment
  }
}

resource "aws_iam_role_policy" "scheduler" {
  name = "invoke-marketing-send-function"
  role = aws_iam_role.scheduler.id
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Sid      = "InvokeMarketingSend"
      Effect   = "Allow"
      Action   = "lambda:InvokeFunction"
      Resource = [aws_lambda_function.fn["marketing-send"].arn, "${aws_lambda_function.fn["marketing-send"].arn}:*"]
    }]
  })
}

# A failed run is the next run's work (recipients are claimed one by one).
resource "aws_lambda_function_event_invoke_config" "send" {
  function_name                = aws_lambda_function.fn["marketing-send"].function_name
  qualifier                    = aws_lambda_alias.live["marketing-send"].name
  maximum_retry_attempts       = 0
  maximum_event_age_in_seconds = 300
}

resource "aws_scheduler_schedule" "send" {
  name                = "${local.prefix}marketing-send"
  group_name          = "default"
  schedule_expression = "rate(2 minutes)"

  flexible_time_window {
    mode = "OFF"
  }

  target {
    arn      = aws_lambda_alias.live["marketing-send"].arn
    role_arn = aws_iam_role.scheduler.arn
    input    = jsonencode({ source = "schedule" })

    retry_policy {
      maximum_retry_attempts       = 0
      maximum_event_age_in_seconds = 300
    }
  }
}

# --- marketing-sync: bookings and orders -----------------------------------------------------

# Statistics are best effort: a failing batch is retried a few times and
# then dropped (no DLQ) rather than holding the stream.
resource "aws_lambda_event_source_mapping" "reservations" {
  event_source_arn               = var.reservation_stream_arn
  function_name                  = aws_lambda_alias.live["marketing-sync"].arn
  starting_position              = "LATEST"
  batch_size                     = 25
  maximum_retry_attempts         = 3
  bisect_batch_on_function_error = true
  function_response_types        = ["ReportBatchItemFailures"]

  filter_criteria {
    filter {
      pattern = jsonencode({
        eventName = ["INSERT", "MODIFY"]
        dynamodb  = { NewImage = { status = { S = ["reserved", "arrived"] } } }
      })
    }
  }

  # Lambda validates stream access when the mapping is created.
  depends_on = [aws_iam_role_policy.fn]
}

resource "aws_lambda_event_source_mapping" "orders" {
  event_source_arn               = var.order_stream_arn
  function_name                  = aws_lambda_alias.live["marketing-sync"].arn
  starting_position              = "LATEST"
  batch_size                     = 25
  maximum_retry_attempts         = 3
  bisect_batch_on_function_error = true
  function_response_types        = ["ReportBatchItemFailures"]

  filter_criteria {
    filter {
      pattern = jsonencode({
        eventName = ["INSERT", "MODIFY"]
        dynamodb  = { NewImage = { paymentStatus = { S = ["paid"] } } }
      })
    }
  }

  depends_on = [aws_iam_role_policy.fn]
}

# --- SES events: bounces and complaints suppress addresses -------------------------------------

resource "aws_sesv2_configuration_set" "marketing" {
  configuration_set_name = local.config

  sending_options {
    sending_enabled = true
  }

  # Hard bounces go on SES's account-level suppression list (the address
  # does not exist, for anyone). Complaints do NOT: that list is shared by
  # every restaurant and by booking confirmations, and a guest who marks one
  # newsletter as spam must still get their booking emails. marketing-sync
  # suppresses complaints per restaurant instead (subscriber status).
  suppression_options {
    suppressed_reasons = ["BOUNCE"]
  }

  tags = {
    Environment = var.environment
  }
}

data "aws_cloudwatch_event_bus" "default" {
  name = "default"
}

resource "aws_sesv2_configuration_set_event_destination" "events" {
  configuration_set_name = aws_sesv2_configuration_set.marketing.configuration_set_name
  event_destination_name = "marketing-events"

  event_destination {
    enabled              = true
    matching_event_types = ["BOUNCE", "COMPLAINT", "DELIVERY"]

    event_bridge_destination {
      event_bus_arn = data.aws_cloudwatch_event_bus.default.arn
    }
  }
}

resource "aws_cloudwatch_event_rule" "ses" {
  name        = "${local.prefix}marketing-ses-events"
  description = "SES bounce/complaint/delivery events for marketing emails -> marketing-sync"
  event_pattern = jsonencode({
    source        = ["aws.ses"]
    "detail-type" = ["Email Bounced", "Email Complaint Received", "Email Delivered"]
    detail        = { mail = { tags = { "ses:configuration-set" = [local.config] } } }
  })

  tags = {
    Environment = var.environment
  }
}

resource "aws_cloudwatch_event_target" "ses" {
  rule = aws_cloudwatch_event_rule.ses.name
  arn  = aws_lambda_alias.live["marketing-sync"].arn
}

resource "aws_lambda_permission" "ses_events" {
  statement_id  = "AllowEventBridgeSesEvents"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.fn["marketing-sync"].function_name
  qualifier     = aws_lambda_alias.live["marketing-sync"].name
  principal     = "events.amazonaws.com"
  source_arn    = aws_cloudwatch_event_rule.ses.arn
}
