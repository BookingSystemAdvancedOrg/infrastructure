# Google Business Profile (feature D, ADR-D, CONTRACTS.md 4, 6.D, 9, 11): connect
# a restaurant's Google profile, push opening hours one way (Booqy is the
# source) and send consent-checked post-visit review requests.
# Application: functions/google-business (JWT routes D1-D10, hooks platform
# D11, tenant.purge, privacy.export/erase), functions/google-business-jobs
# (hourly sync, GuestVisit.Recorded consumer, review sender),
# shared/features/google_business. Google is a simulator unless
# var.google_business_client says "real" (refused in prod at runtime).
#
# All access below is on NEW roles. No existing role, permissions boundary,
# OIDC role, Cognito, CloudFront or KMS key is changed; the hook callers'
# invoke grants were added in Run 0 (security/iam/feature-hooks).

data "aws_caller_identity" "current" {}

locals {
  prefix  = var.environment == "prod" ? "" : "${var.environment}-"
  account = data.aws_caller_identity.current.account_id
  name    = "${local.prefix}google-business"

  tenant_secret_prefix = "booqy/${var.environment}/google-business/"
  tenant_secret_arns   = "arn:aws:secretsmanager:${var.region}:${local.account}:secret:${local.tenant_secret_prefix}*"
  jobs_function_name   = "${local.prefix}google-business-jobs"
  jobs_alias_arn       = "arn:aws:lambda:${var.region}:${local.account}:function:${local.jobs_function_name}:live"
  schedule_group       = "${local.prefix}google-business"
  ses_from             = [var.from_address, "*<${var.from_address}>"]

  common_env = {
    ENVIRONMENT                    = var.environment
    GOOGLE_BUSINESS_TABLE_NAME     = aws_dynamodb_table.this.name
    TENANT_TABLE_NAME              = var.tenant_table_name
    LOCATION_TABLE_NAME            = var.location_table_name
    LOCATION_ID_INDEX_NAME         = var.location_id_index_name
    GOOGLE_BUSINESS_CLIENT         = var.google_business_client
    GOOGLE_BUSINESS_APP_SECRET_ARN = aws_secretsmanager_secret.app.arn
    EVENT_BUS_NAME                 = var.event_bus_name
    SCHEDULE_GROUP_NAME            = local.schedule_group
  }

  functions = {
    google-business = {
      timeout = 28
      memory  = 512
      env = merge(local.common_env, {
        GOOGLE_REDIRECT_URI = "${var.admin_app_url}/installningar?google=1"
      })
    }
    google-business-jobs = {
      timeout = 300
      memory  = 512
      env = merge(local.common_env, {
        RESERVATION_TABLE_NAME        = var.reservation_table_name
        ORDER_TABLE_NAME              = var.order_table_name
        CONSENT_TABLE_NAME            = var.consent_table_name
        SCHEDULER_INVOKE_ROLE_ARN     = aws_iam_role.scheduler.arn
        SCHEDULER_DLQ_ARN             = aws_sqs_queue.dlq.arn
        JOBS_FUNCTION_ARN             = local.jobs_alias_arn
        NO_REPLY_EMAIL_ADDRESS        = var.from_address
        MARKETING_LINK_BASE           = "${var.admin_app_url}/api"
        MARKETING_LINK_KEY_SECRET_ARN = var.marketing_link_key_secret_arn
        MAIL_OUTBOX_BUCKET_NAME       = var.mail_outbox_bucket_name
        NOTIFICATION_FUNCTION_NAME    = var.notification_function_arn
      })
    }
  }

  table_arn = aws_dynamodb_table.this.arn

  common_statements = [
    {
      Sid      = "GoogleBusinessTable"
      Effect   = "Allow"
      Action   = ["dynamodb:GetItem", "dynamodb:PutItem", "dynamodb:UpdateItem", "dynamodb:DeleteItem", "dynamodb:Query", "dynamodb:BatchWriteItem"]
      Resource = [local.table_arn, "${local.table_arn}/index/byLinked"]
    },
    {
      # Per-tenant refresh tokens, created at runtime under booqy/<env>/google-business/.
      Sid      = "TenantTokens"
      Effect   = "Allow"
      Action   = ["secretsmanager:CreateSecret", "secretsmanager:PutSecretValue", "secretsmanager:GetSecretValue", "secretsmanager:DeleteSecret", "secretsmanager:TagResource"]
      Resource = local.tenant_secret_arns
    },
    {
      Sid      = "AppSecret"
      Effect   = "Allow"
      Action   = ["secretsmanager:GetSecretValue"]
      Resource = aws_secretsmanager_secret.app.arn
    },
    {
      # Disconnect, erase and purge delete pending review schedules.
      Sid      = "ReviewSchedules"
      Effect   = "Allow"
      Action   = ["scheduler:DeleteSchedule"]
      Resource = "arn:aws:scheduler:${var.region}:${local.account}:schedule/${local.schedule_group}/*"
    },
    {
      Sid       = "PublishGoogleBusinessEvents"
      Effect    = "Allow"
      Action    = ["events:PutEvents"]
      Resource  = var.event_bus_arn
      Condition = { StringEquals = { "events:source" = "booqy.google-business" } }
    },
  ]

  statements = {
    google-business = local.common_statements
    google-business-jobs = concat(local.common_statements, [
      {
        Sid      = "CreateReviewSchedules"
        Effect   = "Allow"
        Action   = ["scheduler:CreateSchedule"]
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
        # The contact is read from the source row at send time (contactRef).
        Sid      = "ReadSourceRows"
        Effect   = "Allow"
        Action   = ["dynamodb:GetItem"]
        Resource = [var.reservation_table_arn, var.order_table_arn]
      },
      {
        Sid      = "ReadConsentLog"
        Effect   = "Allow"
        Action   = ["dynamodb:Query"]
        Resource = var.consent_table_arn
      },
      {
        # Signs the guest's withdraw link (shared/consent.withdraw_link).
        Sid      = "ReadMarketingLinkKey"
        Effect   = "Allow"
        Action   = ["secretsmanager:GetSecretValue"]
        Resource = var.marketing_link_key_secret_arn
      },
      {
        Sid       = "SendReviewEmail"
        Effect    = "Allow"
        Action    = ["ses:SendRawEmail"]
        Resource  = [var.ses_identity_arn, "arn:aws:ses:${var.region}:${local.account}:identity/*"]
        Condition = { StringLike = { "ses:FromAddress" = local.ses_from } }
      },
      {
        # Review SMS go through notification:live (CONTRACTS.md 9.4), never SNS directly.
        Sid      = "InvokeNotification"
        Effect   = "Allow"
        Action   = ["lambda:InvokeFunction"]
        Resource = var.notification_function_arn
      },
      ], var.mail_outbox_bucket_arn == "" ? [] : [
      {
        Sid      = "WriteDevMailOutbox"
        Effect   = "Allow"
        Action   = ["s3:PutObject"]
        Resource = "${var.mail_outbox_bucket_arn}/outbox/*"
      },
    ])
  }
}

# --- table -------------------------------------------------------------------------------

resource "aws_dynamodb_table" "this" {
  name         = local.name
  billing_mode = "PAY_PER_REQUEST"
  hash_key     = "PK"
  range_key    = "SK"

  # TENANT#<t> / CONNECTION, OAUTH#, GLOC#, REVSENT#; LOCATION#<l> / LINK,
  # REVIEWSETTINGS, REVJOB# (CONTRACTS.md 4)
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

  # Sparse: LINK rows only (the hourly sync lists them without a Scan).
  global_secondary_index {
    name            = "byLinked"
    projection_type = "KEYS_ONLY"

    key_schema {
      attribute_name = "GSI1PK"
      key_type       = "HASH"
    }

    key_schema {
      attribute_name = "GSI1SK"
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

# --- the Google OAuth client (value set by hand) -----------------------------------------

resource "aws_secretsmanager_secret" "app" {
  name                    = "${local.prefix}google-business/app"
  description             = "Google OAuth client, JSON {clientId, clientSecret}; set by hand"
  recovery_window_in_days = var.environment == "prod" ? 30 : 7

  tags = {
    Environment = var.environment
  }
}

# --- functions ---------------------------------------------------------------------------

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

resource "aws_lambda_alias" "live" {
  for_each         = local.functions
  name             = "live"
  function_name    = aws_lambda_function.fn[each.key].function_name
  function_version = aws_lambda_function.fn[each.key].version

  lifecycle {
    ignore_changes = [function_version, routing_config]
  }
}

# --- scheduler: hourly sync + one-time review schedules -----------------------------------

resource "aws_scheduler_schedule_group" "reviews" {
  name = local.schedule_group

  tags = {
    Environment = var.environment
  }
}

resource "aws_sqs_queue" "dlq" {
  name                      = "${local.prefix}google-business-dlq"
  message_retention_seconds = 1209600
  sqs_managed_sse_enabled   = true

  tags = {
    Environment = var.environment
  }
}

resource "aws_iam_role" "scheduler" {
  name = "${local.prefix}scheduler-invoke-google-business-jobs-role"

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
  name = "invoke-google-business-jobs"
  role = aws_iam_role.scheduler.id
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid      = "InvokeJobs"
        Effect   = "Allow"
        Action   = "lambda:InvokeFunction"
        Resource = aws_lambda_alias.live["google-business-jobs"].arn
      },
      {
        Sid      = "DeadLetters"
        Effect   = "Allow"
        Action   = "sqs:SendMessage"
        Resource = aws_sqs_queue.dlq.arn
      },
    ]
  })
}

resource "aws_scheduler_schedule" "sync" {
  name                         = "${local.prefix}google-business-sync"
  group_name                   = "default"
  schedule_expression          = "rate(1 hour)"
  schedule_expression_timezone = "Europe/Stockholm"

  flexible_time_window {
    mode = "OFF"
  }

  target {
    arn      = aws_lambda_alias.live["google-business-jobs"].arn
    role_arn = aws_iam_role.scheduler.arn
    input    = jsonencode({ job = "sync" })

    retry_policy {
      maximum_retry_attempts       = 2
      maximum_event_age_in_seconds = 3600
    }
  }
}

# --- bus rule: GuestVisit.Recorded (guest-crm-sync) -> review schedule --------------------

resource "aws_cloudwatch_event_rule" "guest_visit" {
  name           = "${local.prefix}google-business-guest-visit"
  description    = "Post-visit review requests (ADR-D 4)"
  event_bus_name = var.event_bus_name
  event_pattern = jsonencode({
    source        = ["booqy.guest-crm"]
    "detail-type" = ["GuestVisit.Recorded"]
    detail        = { kind = ["booking", "order"] }
  })

  tags = {
    Environment = var.environment
  }
}

resource "aws_cloudwatch_event_target" "guest_visit" {
  rule           = aws_cloudwatch_event_rule.guest_visit.name
  event_bus_name = var.event_bus_name
  arn            = aws_lambda_alias.live["google-business-jobs"].arn

  dead_letter_config {
    arn = aws_sqs_queue.dlq.arn
  }

  retry_policy {
    maximum_retry_attempts       = 8
    maximum_event_age_in_seconds = 86400
  }
}

resource "aws_lambda_permission" "guest_visit" {
  statement_id  = "AllowGuestVisitRule"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.fn["google-business-jobs"].function_name
  qualifier     = aws_lambda_alias.live["google-business-jobs"].name
  principal     = "events.amazonaws.com"
  source_arn    = aws_cloudwatch_event_rule.guest_visit.arn
}

resource "aws_sqs_queue_policy" "dlq" {
  queue_url = aws_sqs_queue.dlq.id
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Sid       = "RuleDeadLetters"
      Effect    = "Allow"
      Principal = { Service = "events.amazonaws.com" }
      Action    = "sqs:SendMessage"
      Resource  = aws_sqs_queue.dlq.arn
      Condition = { ArnEquals = { "aws:SourceArn" = aws_cloudwatch_event_rule.guest_visit.arn } }
    }]
  })
}

# --- alarms --------------------------------------------------------------------------------

resource "aws_cloudwatch_metric_alarm" "errors" {
  for_each            = local.functions
  alarm_name          = "${local.prefix}${each.key}-errors"
  alarm_description   = "${each.key} Lambda errors"
  namespace           = "AWS/Lambda"
  metric_name         = "Errors"
  dimensions          = { FunctionName = aws_lambda_function.fn[each.key].function_name }
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

resource "aws_cloudwatch_metric_alarm" "dlq" {
  alarm_name          = "${local.prefix}google-business-dlq"
  alarm_description   = "Review request events or schedules that could not be delivered"
  namespace           = "AWS/SQS"
  metric_name         = "ApproximateNumberOfMessagesVisible"
  dimensions          = { QueueName = aws_sqs_queue.dlq.name }
  statistic           = "Maximum"
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
