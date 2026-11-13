# AI phone booking agent (feature L, ADR-L, CONTRACTS.md 4, 5, 6.L, 9, 11, 13, 14).
# Off by default (entitlement `phoneAgent`); voice, telephony and the agent
# model are simulators unless var.voice_client / var.telephony_client /
# var.agent_model_client say "real" (refused in prod at runtime).
# Application: functions/phone-agent (JWT routes L1-L12, hooks platform
# L15-L18, privacy.*, tenant.purge, billing.usage), functions/phone-agent-call
# (provider webhooks L13/L14 and the agent turn endpoint on a Function URL),
# functions/phone-agent-jobs (5-minute sweep, nightly retention),
# shared/features/phone_agent.
#
# All access below is on NEW roles. No existing role, permissions boundary,
# OIDC role, Cognito, CloudFront or KMS key is changed; the hook callers'
# invoke grants on phone-agent:live exist since the Run 0 addendum
# (CONTRACTS.md 14 rows 11, 12, 16). Call-outs (new roles touching existing
# resources): invoke on existing functions' `live` aliases (the agent's
# tools), Put/Delete on the user table limited to `USER#agent:*`, Get/Put on
# the tenant table limited to `PLATFORM#PHONE_AGENT`, Query on the user
# table's tenant index (owner emails for the 80 % warning), invoke
# notification:live.

data "aws_caller_identity" "current" {}

locals {
  prefix    = var.environment == "prod" ? "" : "${var.environment}-"
  account   = data.aws_caller_identity.current.account_id
  name      = "${local.prefix}phone-agent"
  table_arn = aws_dynamodb_table.this.arn
  bucket    = "${local.prefix}phone-agent-recordings-${local.account}"
  # The model itself, or an EU inference profile and the model it routes to (any EU region).
  model_arns = var.phone_agent_model_id == "" ? [] : [
    "arn:aws:bedrock:${var.region}::foundation-model/${var.phone_agent_model_id}",
    "arn:aws:bedrock:${var.region}:${local.account}:inference-profile/${var.phone_agent_model_id}",
    "arn:aws:bedrock:eu-*::foundation-model/${trimprefix(var.phone_agent_model_id, "eu.")}",
  ]

  common_env = {
    ENVIRONMENT            = var.environment
    PHONE_AGENT_TABLE_NAME = aws_dynamodb_table.this.name
    NUMBER_INDEX_NAME      = "byNumber"
    RESERVATION_INDEX_NAME = "byReservation"
    TENANT_TABLE_NAME      = var.tenant_table_name
    LOCATION_TABLE_NAME    = var.location_table_name
    LOCATION_ID_INDEX_NAME = var.location_id_index_name
    USER_TABLE_NAME        = var.user_table_name
    USER_TENANT_INDEX_NAME = var.user_tenant_index_name
    EVENT_BUS_NAME         = var.event_bus_name
    VOICE_CLIENT           = var.voice_client
    TELEPHONY_CLIENT       = var.telephony_client
    AGENT_MODEL_CLIENT     = var.agent_model_client
    PHONE_AGENT_MODEL_ID   = var.phone_agent_model_id
    VOICE_SECRET_ARN       = aws_secretsmanager_secret.voice.arn
    TELEPHONY_SECRET_ARN   = aws_secretsmanager_secret.telephony.arn
    # ElevenLabs (the real voice client): the stock library voice, the TTS
    # model and the API base (EU residency changes it).
    PHONE_AGENT_VOICE_ID  = var.phone_agent_voice_id
    PHONE_AGENT_TTS_MODEL = var.phone_agent_tts_model
    ELEVENLABS_API_BASE   = var.elevenlabs_api_base
  }

  functions = {
    phone-agent = {
      timeout     = 28
      memory      = 512
      concurrency = -1
      env = merge(local.common_env, {
        RECORDINGS_BUCKET = aws_s3_bucket.recordings.bucket
        # The ElevenLabs agent per location references this key (stored as an
        # ElevenLabs workspace secret) for its custom LLM calls.
        LLM_ENDPOINT_KEY_SECRET_ARN = aws_secretsmanager_secret.llm_key.arn
      })
    }
    phone-agent-call = {
      timeout = 30
      memory  = 1024
      # Caps what a flood of calls on the public Function URL can cost. Dev
      # sets 2; prod stays unreserved (-1) until the owner decides a value.
      concurrency = var.call_reserved_concurrency
      env = merge(local.common_env, {
        NOTIFICATION_FUNCTION_NAME  = var.notification_function_arn
        LLM_ENDPOINT_KEY_SECRET_ARN = aws_secretsmanager_secret.llm_key.arn
      })
    }
    phone-agent-jobs = {
      timeout     = 300
      memory      = 512
      concurrency = -1
      env         = local.common_env
    }
  }

  table_statement = {
    Sid      = "PhoneAgentTable"
    Effect   = "Allow"
    Action   = ["dynamodb:GetItem", "dynamodb:PutItem", "dynamodb:UpdateItem", "dynamodb:DeleteItem", "dynamodb:Query", "dynamodb:BatchWriteItem"]
    Resource = [local.table_arn, "${local.table_arn}/index/*"]
  }
  events_statement = {
    Sid       = "PublishPhoneAgentEvents"
    Effect    = "Allow"
    Action    = ["events:PutEvents"]
    Resource  = var.event_bus_arn
    Condition = { StringEquals = { "events:source" = "booqy.phone-agent" } }
  }
  platform_row_read = {
    # The platform kill switch and max cap (console row, like PLATFORM#META_ADS).
    Sid       = "ReadPlatformSettings"
    Effect    = "Allow"
    Action    = ["dynamodb:GetItem"]
    Resource  = var.tenant_table_arn
    Condition = { "ForAllValues:StringEquals" = { "dynamodb:LeadingKeys" = ["PLATFORM#PHONE_AGENT"] } }
  }
  provider_secrets = {
    Sid      = "ProviderSecrets"
    Effect   = "Allow"
    Action   = ["secretsmanager:GetSecretValue"]
    Resource = [aws_secretsmanager_secret.voice.arn, aws_secretsmanager_secret.telephony.arn]
  }
  bedrock_statement = length(local.model_arns) == 0 ? [] : [{
    Sid      = "AgentModel"
    Effect   = "Allow"
    Action   = ["bedrock:InvokeModelWithResponseStream"]
    Resource = local.model_arns
  }]
  read_tools = [var.tool_function_arns["tenant-site-config"], var.tool_function_arns["get-availability"],
  var.tool_function_arns["get-reservation"], var.tool_function_arns["get-menu"], var.tool_function_arns["list-layout-version"]]

  statements = {
    phone-agent = concat([
      local.table_statement, local.events_statement, local.platform_row_read, local.provider_secrets,
      {
        # Console forward L18 writes the platform row.
        Sid       = "WritePlatformSettings"
        Effect    = "Allow"
        Action    = ["dynamodb:PutItem"]
        Resource  = var.tenant_table_arn
        Condition = { "ForAllValues:StringEquals" = { "dynamodb:LeadingKeys" = ["PLATFORM#PHONE_AGENT"] } }
      },
      {
        # The agent principal: one system user per enabled location (ADR-L "The agent principal").
        Sid       = "AgentSystemUsers"
        Effect    = "Allow"
        Action    = ["dynamodb:PutItem", "dynamodb:DeleteItem"]
        Resource  = var.user_table_arn
        Condition = { "ForAllValues:StringLike" = { "dynamodb:LeadingKeys" = ["USER#agent:*"] } }
      },
      {
        # The simulator (L6) runs the read tools; it never writes a booking.
        Sid      = "InvokeReadTools"
        Effect   = "Allow"
        Action   = ["lambda:InvokeFunction"]
        Resource = local.read_tools
      },
      {
        Sid      = "Recordings"
        Effect   = "Allow"
        Action   = ["s3:GetObject", "s3:DeleteObject"]
        Resource = "${aws_s3_bucket.recordings.arn}/recordings/*"
      },
      {
        Sid       = "ListRecordingsForPurge"
        Effect    = "Allow"
        Action    = ["s3:ListBucket"]
        Resource  = aws_s3_bucket.recordings.arn
        Condition = { StringLike = { "s3:prefix" = ["recordings/*"] } }
      },
    ], local.bedrock_statement)
    phone-agent-call = concat([
      local.table_statement, local.events_statement, local.platform_row_read,
      local.provider_secrets,
      {
        Sid      = "EndpointKey"
        Effect   = "Allow"
        Action   = ["secretsmanager:GetSecretValue"]
        Resource = aws_secretsmanager_secret.llm_key.arn
      },
      {
        # The agent's tools: the existing functions on their live alias (no table access).
        Sid      = "InvokeTools"
        Effect   = "Allow"
        Action   = ["lambda:InvokeFunction"]
        Resource = values(var.tool_function_arns)
      },
      {
        Sid      = "InvokeNotification"
        Effect   = "Allow"
        Action   = ["lambda:InvokeFunction"]
        Resource = var.notification_function_arn
      },
      {
        # Owner e-mails for the 80 % minutes warning.
        Sid      = "FindOwners"
        Effect   = "Allow"
        Action   = ["dynamodb:Query"]
        Resource = "${var.user_table_arn}/index/${var.user_tenant_index_name}"
      },
    ], local.bedrock_statement)
    phone-agent-jobs = [
      local.table_statement, local.events_statement, local.platform_row_read,
      local.provider_secrets,
      {
        # The sweep and the nightly retention read the table by row kind.
        Sid      = "ScanPhoneAgentTable"
        Effect   = "Allow"
        Action   = ["dynamodb:Scan"]
        Resource = local.table_arn
      },
    ]
  }
}

# --- table -------------------------------------------------------------------------------

resource "aws_dynamodb_table" "this" {
  name         = local.name
  billing_mode = "PAY_PER_REQUEST"
  hash_key     = "PK"
  range_key    = "SK"

  # TENANT#<t> / CONFIG, LOC#<l>#CONFIG, NUMBER#<e164>, CALL#<day>#<callId>[#T#<seq>],
  # CALLBACK#<id>, USAGE#<periodEnd>, SIM#<sessionId> (CONTRACTS.md 4)
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

  # Sparse: NUMBER# rows; the inbound webhook resolves the called number.
  global_secondary_index {
    name            = "byNumber"
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

  # Sparse: CALL# rows that booked a reservation (the Bokningar badge, L12).
  global_secondary_index {
    name            = "byReservation"
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

  # Turns 24 months, CALL 7 years, CALLBACK 90 days after close, SIM 1 hour
  # ([NEEDS YOUR OK: retention]).
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

# --- recordings (only with the tenant's opt-in; off by default) ----------------------------

resource "aws_s3_bucket" "recordings" {
  bucket = local.bucket

  tags = {
    Environment = var.environment
  }
}

resource "aws_s3_bucket_public_access_block" "recordings" {
  bucket                  = aws_s3_bucket.recordings.id
  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

resource "aws_s3_bucket_server_side_encryption_configuration" "recordings" {
  bucket = aws_s3_bucket.recordings.id

  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm = "AES256"
    }
  }
}

resource "aws_s3_bucket_ownership_controls" "recordings" {
  bucket = aws_s3_bucket.recordings.id

  rule {
    object_ownership = "BucketOwnerEnforced"
  }
}

# Each recording carries the tag retention = 7 | 30 | 90 (the tenant's choice).
resource "aws_s3_bucket_lifecycle_configuration" "recordings" {
  bucket = aws_s3_bucket.recordings.id

  dynamic "rule" {
    for_each = toset(["7", "30", "90"])
    content {
      id     = "retention-${rule.value}-days"
      status = "Enabled"

      filter {
        tag {
          key   = "retention"
          value = rule.value
        }
      }

      expiration {
        days = tonumber(rule.value)
      }
    }
  }
}

# --- secrets -------------------------------------------------------------------------------

resource "aws_secretsmanager_secret" "voice" {
  name                    = "${local.prefix}phone-agent/voice-provider"
  description             = "ElevenLabs, JSON {apiKey, webhookSecret, initiationToken, callUrl}; set by hand"
  recovery_window_in_days = var.environment == "prod" ? 30 : 7

  tags = {
    Environment = var.environment
  }
}

resource "aws_secretsmanager_secret" "telephony" {
  name                    = "${local.prefix}phone-agent/telephony"
  description             = "46elks, JSON {username, password, webhookToken}; set by hand"
  recovery_window_in_days = var.environment == "prod" ? 30 : 7

  tags = {
    Environment = var.environment
  }
}

resource "random_password" "llm_key" {
  length  = 48
  special = false
}

resource "aws_secretsmanager_secret" "llm_key" {
  name                    = "${local.prefix}phone-agent/llm-endpoint-key"
  description             = "Header secret the voice provider sends to the agent turn endpoint"
  recovery_window_in_days = var.environment == "prod" ? 30 : 7

  tags = {
    Environment = var.environment
  }
}

resource "aws_secretsmanager_secret_version" "llm_key" {
  secret_id     = aws_secretsmanager_secret.llm_key.id
  secret_string = random_password.llm_key.result
}

# --- functions -----------------------------------------------------------------------------

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

# The agent turn endpoint (not an API Gateway route): the voice provider calls
# POST /v1/chat/completions with the endpoint key header; the function checks
# the key and refuses unknown or ended calls. Buffered for now; response
# streaming needs the Lambda Web Adapter image (ADR-L 3).
resource "aws_lambda_function_url" "turn" {
  function_name      = aws_lambda_function.fn["phone-agent-call"].function_name
  qualifier          = aws_lambda_alias.live["phone-agent-call"].name
  authorization_type = "NONE"
  invoke_mode        = "BUFFERED"
}

# --- schedules: sweep every 5 minutes, retention nightly ------------------------------------

resource "aws_iam_role" "scheduler" {
  name = "${local.prefix}scheduler-invoke-phone-agent-role"

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
  name = "invoke-phone-agent-jobs"
  role = aws_iam_role.scheduler.id
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Sid      = "InvokeJobs"
      Effect   = "Allow"
      Action   = "lambda:InvokeFunction"
      Resource = aws_lambda_alias.live["phone-agent-jobs"].arn
    }]
  })
}

resource "aws_scheduler_schedule" "jobs" {
  for_each = {
    sweep   = "rate(5 minutes)"
    nightly = "cron(0 3 * * ? *)"
  }
  name                         = "${local.prefix}phone-agent-${each.key}"
  group_name                   = "default"
  schedule_expression          = each.value
  schedule_expression_timezone = "Europe/Stockholm"

  flexible_time_window {
    mode = "OFF"
  }

  target {
    arn      = aws_lambda_alias.live["phone-agent-jobs"].arn
    role_arn = aws_iam_role.scheduler.arn
    input    = jsonencode({ job = each.key })

    retry_policy {
      maximum_retry_attempts       = 1
      maximum_event_age_in_seconds = 600
    }
  }
}

# --- alarms (ADR-L 9) -----------------------------------------------------------------------

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

resource "aws_cloudwatch_metric_alarm" "billed_minutes" {
  alarm_name          = "${local.name}-billed-minutes-per-day"
  alarm_description   = "Phone agent minutes in one day above the platform threshold"
  namespace           = "Booqy/PhoneAgent"
  metric_name         = "BilledMinutes"
  statistic           = "Sum"
  period              = 86400
  evaluation_periods  = 1
  threshold           = var.daily_minutes_alarm
  comparison_operator = "GreaterThanThreshold"
  treat_missing_data  = "notBreaching"
  alarm_actions       = [var.alert_topic_arn]

  tags = {
    Environment = var.environment
  }
}

resource "aws_cloudwatch_metric_alarm" "provider_errors" {
  alarm_name          = "${local.name}-provider-errors"
  alarm_description   = "Voice provider or agent model errors on calls"
  namespace           = "Booqy/PhoneAgent"
  metric_name         = "ProviderErrors"
  statistic           = "Sum"
  period              = 300
  evaluation_periods  = 1
  threshold           = 5
  comparison_operator = "GreaterThanThreshold"
  treat_missing_data  = "notBreaching"
  alarm_actions       = [var.alert_topic_arn]

  tags = {
    Environment = var.environment
  }
}

resource "aws_cloudwatch_metric_alarm" "turn_latency" {
  alarm_name          = "${local.name}-turn-latency-p95"
  alarm_description   = "Agent turn latency p95 above 2.5 s for 15 minutes"
  namespace           = "Booqy/PhoneAgent"
  metric_name         = "TurnLatencyMs"
  extended_statistic  = "p95"
  period              = 300
  evaluation_periods  = 3
  threshold           = 2500
  comparison_operator = "GreaterThanThreshold"
  treat_missing_data  = "notBreaching"
  alarm_actions       = [var.alert_topic_arn]

  tags = {
    Environment = var.environment
  }
}
