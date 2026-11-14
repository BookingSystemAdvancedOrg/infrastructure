# In-app help assistant: answers "how do I ..." questions in Booqy Admin from
# a curated help knowledge base (application shared/help_kb.json, synced from
# admin-front-end src/features/help/helpKb.json) and returns navigation
# buttons. Application: functions/help-assistant.
#
# Off unless var.enabled; the PLATFORM#HELP_ASSISTANT/SETTINGS row switches it
# off at runtime (read through the tenant-context policy). Bedrock is only
# called with BEDROCK_CLIENT=real and a model id; otherwise, and past the
# monthly answer caps, answers are built from the knowledge base alone.
# Per-user rate limit and the caps are counters in the request-guard table.
# Nothing the user types is stored or logged.

data "aws_caller_identity" "current" {}

locals {
  prefix        = var.environment == "prod" ? "" : "${var.environment}-"
  account       = data.aws_caller_identity.current.account_id
  function_name = "${local.prefix}help-assistant"
  # An EU inference profile (eu.<model>) routes to the model in any EU region.
  profile_model = startswith(var.bedrock_model_id, "eu.") ? trimprefix(var.bedrock_model_id, "eu.") : ""

  statements = concat([
    {
      # Rate limit per user and the monthly answer caps (hashed keys, TTL).
      Sid      = "RequestGuardCounters"
      Effect   = "Allow"
      Action   = ["dynamodb:UpdateItem"]
      Resource = var.request_guard_table_arn
    },
    ], var.bedrock_model_id == "" ? [] : [
    {
      Sid    = "AnswerHelpQuestions"
      Effect = "Allow"
      Action = ["bedrock:InvokeModel"]
      Resource = concat([
        "arn:aws:bedrock:${var.region}::foundation-model/${var.bedrock_model_id}",
        "arn:aws:bedrock:${var.region}:${local.account}:inference-profile/${var.bedrock_model_id}",
      ], local.profile_model == "" ? [] : ["arn:aws:bedrock:eu-*::foundation-model/${local.profile_model}"])
    },
  ])
}

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
  name   = "help-assistant-access"
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
  memory_size   = 1024

  lifecycle {
    ignore_changes = [image_uri]
  }

  environment {
    variables = {
      ENVIRONMENT                     = var.environment
      TENANT_TABLE_NAME               = var.tenant_table_name
      LOCATION_TABLE_NAME             = var.location_table_name
      LOCATION_ID_INDEX_NAME          = var.location_id_index_name
      REQUEST_GUARD_TABLE_NAME        = var.request_guard_table_name
      HELP_ASSISTANT_ENABLED          = var.enabled ? "true" : "false"
      HELP_ASSISTANT_TENANT_MONTHLY   = tostring(var.monthly_answers.per_tenant)
      HELP_ASSISTANT_PLATFORM_MONTHLY = tostring(var.monthly_answers.total)
      BEDROCK_CLIENT                  = var.bedrock_client
      BEDROCK_MODEL_ID                = var.bedrock_model_id
      HELP_APP_URL_ADMIN              = var.app_urls["admin"]
      HELP_APP_URL_CONSOLE            = var.app_urls["console"]
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

# --- alarms --------------------------------------------------------------------------------

resource "aws_cloudwatch_metric_alarm" "errors" {
  alarm_name          = "${local.function_name}-errors"
  alarm_description   = "help-assistant Lambda errors"
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
