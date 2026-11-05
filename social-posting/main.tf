# Organic Facebook and Instagram posting (feature G, ADR-G, CONTRACTS.md 4, 6.G,
# 11, 13): one function for the routes, the scheduled publish worker and the
# MetaConnection.Disconnected consumer. Application: functions/social-posting,
# shared/features/social_posting. Meta is A's port (simulator unless
# var.meta_client says "real", refused in prod at runtime).
#
# No token storage: the role reads feature A's per-tenant secret (Get only,
# never Put/Create/Delete) and A's CONNECTION rows (GetItem only). All access
# is on the NEW role; no existing role changes (tenant-purge's invoke grant on
# social-posting:live exists since Run 0).

data "aws_caller_identity" "current" {}

locals {
  prefix         = var.environment == "prod" ? "" : "${var.environment}-"
  account        = data.aws_caller_identity.current.account_id
  function_name  = "${local.prefix}social-posting"
  self_alias_arn = "arn:aws:lambda:${var.region}:${local.account}:function:${local.function_name}:live"
  schedule_group = "${local.prefix}social-posting"
  table_arn      = aws_dynamodb_table.this.arn

  statements = [
    {
      Sid      = "SocialPostingTable"
      Effect   = "Allow"
      Action   = ["dynamodb:GetItem", "dynamodb:PutItem", "dynamodb:UpdateItem", "dynamodb:DeleteItem", "dynamodb:Query", "dynamodb:BatchWriteItem"]
      Resource = local.table_arn
    },
    {
      Sid      = "ReadMenuItems"
      Effect   = "Allow"
      Action   = ["dynamodb:GetItem", "dynamodb:Query"]
      Resource = var.menu_table_arn
    },
    {
      # Presigned GET of the dish photo for Meta (15 minutes).
      Sid      = "ReadMenuImages"
      Effect   = "Allow"
      Action   = ["s3:GetObject"]
      Resource = "${var.menu_image_bucket_arn}/menu-images/*"
    },
    {
      # Feature A's per-tenant Meta token: read only (ADR-G 1).
      Sid      = "ReadMetaToken"
      Effect   = "Allow"
      Action   = ["secretsmanager:GetSecretValue"]
      Resource = "arn:aws:secretsmanager:${var.region}:${local.account}:secret:${var.meta_ads_tenant_secret_prefix}*"
    },
    {
      Sid       = "ReadMetaConnection"
      Effect    = "Allow"
      Action    = ["dynamodb:GetItem"]
      Resource  = var.meta_ads_table_arn
      Condition = { "ForAllValues:StringLike" = { "dynamodb:LeadingKeys" = ["TENANT#*"] } }
    },
    {
      Sid      = "PostTimers"
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
      # "Publicera nu" runs the worker asynchronously on its own alias.
      Sid      = "PublishNow"
      Effect   = "Allow"
      Action   = ["lambda:InvokeFunction"]
      Resource = local.self_alias_arn
    },
    {
      Sid       = "PublishSocialPostingEvents"
      Effect    = "Allow"
      Action    = ["events:PutEvents"]
      Resource  = var.event_bus_arn
      Condition = { StringEquals = { "events:source" = "booqy.social-posting" } }
    },
  ]
}

# --- table -------------------------------------------------------------------------------

resource "aws_dynamodb_table" "this" {
  name         = local.function_name
  billing_mode = "PAY_PER_REQUEST"
  hash_key     = "PK"
  range_key    = "SK"

  # TENANT#<t> / POST#<postId> (CONTRACTS.md 4)
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
  name   = "social-posting-access"
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
  timeout       = 120 # API answers in seconds; a publish run may wait on Meta
  memory_size   = 512

  lifecycle {
    ignore_changes = [image_uri]
  }

  environment {
    variables = {
      ENVIRONMENT               = var.environment
      SOCIAL_POSTING_TABLE_NAME = aws_dynamodb_table.this.name
      TENANT_TABLE_NAME         = var.tenant_table_name
      LOCATION_TABLE_NAME       = var.location_table_name
      LOCATION_ID_INDEX_NAME    = var.location_id_index_name
      MENU_TABLE_NAME           = var.menu_table_name
      MENU_IMAGES_BUCKET_NAME   = var.menu_image_bucket_name
      META_ADS_TABLE_NAME       = var.meta_ads_table_name
      META_CLIENT               = var.meta_client
      EVENT_BUS_NAME            = var.event_bus_name
      SCHEDULE_GROUP_NAME       = local.schedule_group
      SCHEDULER_INVOKE_ROLE_ARN = aws_iam_role.scheduler.arn
      SELF_FUNCTION_ARN         = local.self_alias_arn
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

# --- scheduled posts ------------------------------------------------------------------------

resource "aws_scheduler_schedule_group" "posts" {
  name = local.schedule_group

  tags = {
    Environment = var.environment
  }
}

resource "aws_iam_role" "scheduler" {
  name = "${local.prefix}scheduler-invoke-social-posting-role"

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
  name = "invoke-social-posting"
  role = aws_iam_role.scheduler.id
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Sid      = "InvokeSocialPosting"
      Effect   = "Allow"
      Action   = "lambda:InvokeFunction"
      Resource = aws_lambda_alias.live.arn
    }]
  })
}

# --- bus rule: MetaConnection.Disconnected (feature A) ------------------------------------

resource "aws_sqs_queue" "dlq" {
  name                      = "${local.prefix}social-posting-dlq"
  message_retention_seconds = 1209600
  sqs_managed_sse_enabled   = true

  tags = {
    Environment = var.environment
  }
}

resource "aws_cloudwatch_event_rule" "meta_disconnected" {
  name           = "${local.prefix}social-posting-meta-disconnected"
  description    = "Scheduled posts go back to draft when Meta is disconnected (ADR-G)"
  event_bus_name = var.event_bus_name
  event_pattern = jsonencode({
    source        = ["booqy.meta-ads"]
    "detail-type" = ["MetaConnection.Disconnected"]
  })

  tags = {
    Environment = var.environment
  }
}

resource "aws_cloudwatch_event_target" "meta_disconnected" {
  rule           = aws_cloudwatch_event_rule.meta_disconnected.name
  event_bus_name = var.event_bus_name
  arn            = aws_lambda_alias.live.arn

  dead_letter_config {
    arn = aws_sqs_queue.dlq.arn
  }

  retry_policy {
    maximum_retry_attempts       = 8
    maximum_event_age_in_seconds = 86400
  }
}

resource "aws_lambda_permission" "meta_disconnected" {
  statement_id  = "AllowMetaDisconnectedRule"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.fn.function_name
  qualifier     = aws_lambda_alias.live.name
  principal     = "events.amazonaws.com"
  source_arn    = aws_cloudwatch_event_rule.meta_disconnected.arn
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
      Condition = { ArnEquals = { "aws:SourceArn" = aws_cloudwatch_event_rule.meta_disconnected.arn } }
    }]
  })
}

# --- alarms --------------------------------------------------------------------------------

resource "aws_cloudwatch_metric_alarm" "errors" {
  alarm_name          = "${local.function_name}-errors"
  alarm_description   = "social-posting Lambda errors"
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
