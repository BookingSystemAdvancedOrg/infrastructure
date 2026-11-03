# Meta ads (feature A, ADR-A, CONTRACTS.md 4, 6.A, 9.3, 11): Facebook Login for
# Business, the 2-minute ad wizard, the publish workflow and nightly insights.
# Application: functions/meta-ads (API A1-A13, platform hook A14-A17,
# tenant.purge), functions/meta-ads-jobs (workflow tasks, insights, sweep),
# shared/features/meta_ads. Meta and Bedrock are simulators unless
# var.meta_client / var.bedrock_client say "real" (refused in prod at runtime).
#
# Spend is bounded three ways: lifetime budget + end date on every ad set
# (Meta stops by itself), Booqy caps checked on create/activate, and the kill
# switch (PLATFORM#META_ADS/SETTINGS on the tenant table) swept every 15 min.

data "aws_caller_identity" "current" {}

locals {
  prefix  = var.environment == "prod" ? "" : "${var.environment}-"
  account = data.aws_caller_identity.current.account_id

  tenant_secret_prefix = "booqy/${var.environment}/meta-ads/"
  tenant_secret_arns   = "arn:aws:secretsmanager:${var.region}:${local.account}:secret:${local.tenant_secret_prefix}*"
  state_machine_name   = "${local.prefix}meta-ads-publish"
  state_machine_arn    = "arn:aws:states:${var.region}:${local.account}:stateMachine:${local.state_machine_name}"
  jobs_function_name   = "${local.prefix}meta-ads-jobs"

  common_env = {
    ENVIRONMENT          = var.environment
    META_ADS_TABLE_NAME  = aws_dynamodb_table.this.name
    TENANT_TABLE_NAME    = var.tenant_table_name
    MARKETING_TABLE_NAME = var.marketing_table_name
    EVENT_BUS_NAME       = var.event_bus_name
    META_CLIENT          = var.meta_client
    META_APP_SECRET_ARN  = aws_secretsmanager_secret.app.arn
  }

  functions = {
    meta-ads = {
      timeout = 28
      memory  = 512
      env = merge(local.common_env, {
        LOCATION_TABLE_NAME       = var.location_table_name
        LOCATION_ID_INDEX_NAME    = var.location_id_index_name
        MENU_TABLE_NAME           = var.menu_table_name
        PUBLISH_STATE_MACHINE_ARN = local.state_machine_arn
        META_REDIRECT_URI         = "${var.admin_app_url}/marknadsforing?flik=annonser"
        SITE_BASE_DOMAIN          = var.site_domain
        JOBS_FUNCTION_NAME        = "${local.jobs_function_name}:live"
        BEDROCK_CLIENT            = var.bedrock_client
        BEDROCK_MODEL_ID          = var.bedrock_model_id
      })
    }
    meta-ads-jobs = {
      timeout = 300
      memory  = 512
      env = merge(local.common_env, {
        USER_TABLE_NAME            = var.user_table_name
        USER_TENANT_INDEX_NAME     = var.user_tenant_index_name
        MENU_IMAGES_BUCKET_NAME    = var.menu_image_bucket_name
        NOTIFICATION_FUNCTION_NAME = var.notification_function_arn
        PUBLISH_STATE_MACHINE_ARN  = local.state_machine_arn
      })
    }
  }

  table_arn = aws_dynamodb_table.this.arn

  common_statements = [
    {
      Sid      = "MetaAdsTable"
      Effect   = "Allow"
      Action   = ["dynamodb:GetItem", "dynamodb:PutItem", "dynamodb:UpdateItem", "dynamodb:DeleteItem", "dynamodb:Query", "dynamodb:BatchWriteItem"]
      Resource = [local.table_arn, "${local.table_arn}/index/byConnected"]
    },
    {
      # Per-tenant Meta tokens, created at runtime under booqy/<env>/meta-ads/.
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
      # Attribution: read-only on the cookieless counters.
      Sid      = "ReadMarketingStats"
      Effect   = "Allow"
      Action   = ["dynamodb:Query"]
      Resource = var.marketing_table_arn
    },
    {
      # The platform kill switch row (one row, read by both functions).
      Sid       = "ReadKillSwitch"
      Effect    = "Allow"
      Action    = ["dynamodb:GetItem"]
      Resource  = var.tenant_table_arn
      Condition = { "ForAllValues:StringEquals" = { "dynamodb:LeadingKeys" = ["PLATFORM#META_ADS"] } }
    },
    {
      Sid       = "PublishMetaAdsEvents"
      Effect    = "Allow"
      Action    = ["events:PutEvents"]
      Resource  = var.event_bus_arn
      Condition = { StringEquals = { "events:source" = "booqy.meta-ads" } }
    },
  ]

  bedrock_statements = var.bedrock_model_id == "" ? [] : [
    {
      Sid    = "SuggestAdCopy"
      Effect = "Allow"
      Action = ["bedrock:InvokeModel"]
      Resource = [
        "arn:aws:bedrock:${var.region}::foundation-model/${var.bedrock_model_id}",
        "arn:aws:bedrock:${var.region}:${local.account}:inference-profile/${var.bedrock_model_id}",
      ]
    },
  ]

  statements = {
    meta-ads = concat(local.common_statements, local.bedrock_statements, [
      {
        Sid      = "ReadMenuItems"
        Effect   = "Allow"
        Action   = ["dynamodb:GetItem"]
        Resource = var.menu_table_arn
      },
      {
        # Operators set the kill switch through the console's platform hook (A15).
        Sid       = "WriteKillSwitch"
        Effect    = "Allow"
        Action    = ["dynamodb:PutItem"]
        Resource  = var.tenant_table_arn
        Condition = { "ForAllValues:StringEquals" = { "dynamodb:LeadingKeys" = ["PLATFORM#META_ADS"] } }
      },
      {
        Sid      = "StartPublishWorkflow"
        Effect   = "Allow"
        Action   = ["states:StartExecution"]
        Resource = local.state_machine_arn
      },
      {
        Sid      = "SweepAfterKillSwitch"
        Effect   = "Allow"
        Action   = ["lambda:InvokeFunction"]
        Resource = "arn:aws:lambda:${var.region}:${local.account}:function:${local.jobs_function_name}:live"
      },
    ])
    meta-ads-jobs = concat(local.common_statements, [
      {
        # Menu photos only, read when the ad image is uploaded to Meta.
        Sid      = "ReadMenuImages"
        Effect   = "Allow"
        Action   = ["s3:GetObject"]
        Resource = "${var.menu_image_bucket_arn}/menu-images/*"
      },
      {
        # 80 % cap mail goes to the tenant's owners.
        Sid      = "FindOwners"
        Effect   = "Allow"
        Action   = ["dynamodb:Query"]
        Resource = "${var.user_table_arn}/index/${var.user_tenant_index_name}"
      },
      {
        Sid      = "SendCapWarning"
        Effect   = "Allow"
        Action   = ["lambda:InvokeFunction"]
        Resource = var.notification_function_arn
      },
      {
        # The 15-minute sweep starts a publish whose StartExecution was lost
        # (same execution name as A8, so never a second execution).
        Sid      = "RestartStrandedPublish"
        Effect   = "Allow"
        Action   = ["states:StartExecution"]
        Resource = local.state_machine_arn
      },
      {
        Sid       = "PlatformSpendMetric"
        Effect    = "Allow"
        Action    = ["cloudwatch:PutMetricData"]
        Resource  = "*"
        Condition = { StringEquals = { "cloudwatch:namespace" = "Booqy/MetaAds" } }
      },
    ])
  }
}

# --- table -------------------------------------------------------------------------------

resource "aws_dynamodb_table" "this" {
  name         = "${local.prefix}meta-ads"
  billing_mode = "PAY_PER_REQUEST"
  hash_key     = "PK"
  range_key    = "SK"

  # TENANT#<t> / CONNECTION, OAUTH#, CAMPAIGN#, INSIGHT#, SPEND#, COPYUSE# (CONTRACTS.md 4)
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

  # Sparse: connected tenants only (nightly jobs list them without a Scan).
  global_secondary_index {
    name            = "byConnected"
    hash_key        = "GSI1PK"
    range_key       = "GSI1SK"
    projection_type = "KEYS_ONLY"
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

# --- the Meta app (value set by hand) ----------------------------------------------------

resource "aws_secretsmanager_secret" "app" {
  name                    = "${local.prefix}meta-ads/app"
  description             = "Meta app id/secret and Facebook Login for Business configuration id, JSON {appId, appSecret, configId}; set by hand"
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

# --- publish workflow --------------------------------------------------------------------

resource "aws_iam_role" "workflow" {
  name = "${local.prefix}meta-ads-publish-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect    = "Allow"
      Principal = { Service = "states.amazonaws.com" }
      Action    = "sts:AssumeRole"
    }]
  })

  tags = {
    Environment = var.environment
  }
}

resource "aws_iam_role_policy" "workflow" {
  name = "invoke-meta-ads-jobs"
  role = aws_iam_role.workflow.id
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid      = "RunTasks"
        Effect   = "Allow"
        Action   = ["lambda:InvokeFunction"]
        Resource = aws_lambda_alias.live["meta-ads-jobs"].arn
      },
      {
        Sid      = "ExecutionLogs"
        Effect   = "Allow"
        Action   = ["logs:CreateLogDelivery", "logs:GetLogDelivery", "logs:UpdateLogDelivery", "logs:DeleteLogDelivery", "logs:ListLogDeliveries", "logs:PutResourcePolicy", "logs:DescribeResourcePolicies", "logs:DescribeLogGroups"]
        Resource = "*"
      },
    ]
  })
}

resource "aws_cloudwatch_log_group" "workflow" {
  name              = "/aws/vendedlogs/states/${local.state_machine_name}"
  retention_in_days = 30

  tags = {
    Environment = var.environment
  }
}

resource "aws_sfn_state_machine" "publish" {
  name     = local.state_machine_name
  role_arn = aws_iam_role.workflow.arn
  type     = "STANDARD"
  definition = templatefile("${path.module}/definitions/publish.asl.json", {
    jobs_alias_arn = aws_lambda_alias.live["meta-ads-jobs"].arn
    steps          = ["CheckGuards", "UploadImage", "CreateCampaign", "CreateAdSet", "CreateCreative", "CreateAd", "MarkPaused"]
  })

  logging_configuration {
    log_destination        = "${aws_cloudwatch_log_group.workflow.arn}:*"
    include_execution_data = false # inputs hold only ids, but the default keeps logs lean
    level                  = "ERROR"
  }

  tags = {
    Environment = var.environment
  }
}

# --- schedules: nightly insights (04:00 Stockholm), kill-switch sweep ---------------------

resource "aws_iam_role" "scheduler" {
  name = "${local.prefix}scheduler-invoke-meta-ads-jobs-role"

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
  name = "invoke-meta-ads-jobs"
  role = aws_iam_role.scheduler.id
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Sid      = "InvokeJobs"
      Effect   = "Allow"
      Action   = "lambda:InvokeFunction"
      Resource = aws_lambda_alias.live["meta-ads-jobs"].arn
    }]
  })
}

resource "aws_scheduler_schedule" "jobs" {
  for_each = {
    insights = { expression = "cron(0 4 * * ? *)", input = { job = "insights" } }
    sweep    = { expression = "rate(15 minutes)", input = { job = "sweep" } }
  }

  name                         = "${local.prefix}meta-ads-${each.key}"
  group_name                   = "default"
  schedule_expression          = each.value.expression
  schedule_expression_timezone = "Europe/Stockholm"

  flexible_time_window {
    mode = "OFF"
  }

  target {
    arn      = aws_lambda_alias.live["meta-ads-jobs"].arn
    role_arn = aws_iam_role.scheduler.arn
    input    = jsonencode(each.value.input)

    retry_policy {
      maximum_retry_attempts       = 2
      maximum_event_age_in_seconds = 3600
    }
  }
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

resource "aws_cloudwatch_metric_alarm" "publish_failed" {
  alarm_name          = "${local.state_machine_name}-failed"
  alarm_description   = "Meta ads publish executions that failed"
  namespace           = "AWS/States"
  metric_name         = "ExecutionsFailed"
  dimensions          = { StateMachineArn = aws_sfn_state_machine.publish.arn }
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

# Daily sum of every restaurant's Meta spend (nightly insights publish it).
resource "aws_cloudwatch_metric_alarm" "spend" {
  alarm_name          = "${local.prefix}meta-ads-platform-spend"
  alarm_description   = "All restaurants' Meta ad spend in one day is above ${var.platform_daily_spend_alarm_sek} SEK"
  namespace           = "Booqy/MetaAds"
  metric_name         = "PlatformSpendSek"
  statistic           = "Sum"
  period              = 86400
  evaluation_periods  = 1
  threshold           = var.platform_daily_spend_alarm_sek
  comparison_operator = "GreaterThanThreshold"
  treat_missing_data  = "notBreaching"
  alarm_actions       = [var.alert_topic_arn]

  tags = {
    Environment = var.environment
  }
}
