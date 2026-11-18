# Kom igång (application functions/tenant-setup, docs/SETUP-CHECKLIST.md):
# the one rule for "this restaurant has finished its setup", for every
# location of a tenant. GET /tenant/setup and PUT /tenant/setup/skips
# (owner) serve Booqy Admin's checklist; every evaluation stores
# PROFILE.setupState, the first complete one sets setupCompletedAt once with
# an audit row and a NOTICES row (Booqy Console's bell), then puts
# Tenant.SetupCompleted on the bus and emails the operators (alerts topic).
# A sweep every 15 minutes keeps the console's progress current.

data "aws_caller_identity" "current" {}

locals {
  prefix        = var.environment == "prod" ? "" : "${var.environment}-"
  account       = data.aws_caller_identity.current.account_id
  function_name = "${local.prefix}tenant-setup"
  table_arn     = "arn:aws:dynamodb:${var.region}:${local.account}:table"
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

# Writes: PROFILE (setupState, setupCompletedAt only), SETUPSKIP# and AUDIT#
# rows of a tenant, and the NOTICES partition; the first completion is one
# TransactWriteItems. Reads: the tenant list (GSI1, the sweep), a tenant's
# locations, and the step facts in the other tables (Query/GetItem only, no
# Scan, no writes there). Events: only source booqy.tenant-setup. SNS: the
# alerts topic.
resource "aws_iam_role_policy" "fn" {
  name = "tenant-setup-access"
  role = aws_iam_role.fn.id
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid      = "SetupStateOnProfile"
        Effect   = "Allow"
        Action   = ["dynamodb:UpdateItem"]
        Resource = var.tenant_table_arn
        Condition = {
          "ForAllValues:StringEquals" = {
            "dynamodb:Attributes" = ["PK", "SK", "setupState", "setupCompletedAt"]
          }
          StringEqualsIfExists = {
            "dynamodb:ReturnValues" = ["NONE", "UPDATED_OLD", "UPDATED_NEW"]
          }
        }
      },
      {
        Sid      = "SkipsAuditNotices"
        Effect   = "Allow"
        Action   = ["dynamodb:PutItem", "dynamodb:DeleteItem"]
        Resource = var.tenant_table_arn
      },
      {
        Sid      = "ListTenants"
        Effect   = "Allow"
        Action   = ["dynamodb:Query"]
        Resource = "${var.tenant_table_arn}/index/GSI1"
      },
      {
        Sid      = "TenantLocations"
        Effect   = "Allow"
        Action   = ["dynamodb:Query"]
        Resource = var.location_table_arn
      },
      {
        Sid      = "StaffCount"
        Effect   = "Allow"
        Action   = ["dynamodb:Query"]
        Resource = "${var.user_table_arn}/index/${var.user_tenant_index_name}"
      },
      {
        Sid    = "StepFacts"
        Effect = "Allow"
        Action = ["dynamodb:GetItem", "dynamodb:Query"]
        Resource = [
          var.menu_table_arn,
          var.print_table_arn,
          var.published_layout_snapshot_table_arn,
          "${local.table_arn}/${var.google_business_table_name}",
          "${local.table_arn}/${var.phone_agent_table_name}",
        ]
      },
      {
        Sid       = "PublishSetupEvents"
        Effect    = "Allow"
        Action    = ["events:PutEvents"]
        Resource  = var.event_bus_arn
        Condition = { StringEquals = { "events:source" = "booqy.tenant-setup" } }
      },
      {
        Sid      = "NotifyOperators"
        Effect   = "Allow"
        Action   = "sns:Publish"
        Resource = var.alert_topic_arn
      },
    ]
  })
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
  timeout       = 60
  memory_size   = 256

  lifecycle {
    ignore_changes = [image_uri]
  }

  environment {
    variables = {
      ENVIRONMENT                          = var.environment
      TENANT_TABLE_NAME                    = var.tenant_table_name
      LOCATION_TABLE_NAME                  = var.location_table_name
      LOCATION_ID_INDEX_NAME               = var.location_id_index_name
      USER_TABLE_NAME                      = var.user_table_name
      USER_TENANT_INDEX_NAME               = var.user_tenant_index_name
      MENU_TABLE_NAME                      = var.menu_table_name
      PRINT_TABLE_NAME                     = var.print_table_name
      PUBLISHED_LAYOUT_SNAPSHOT_TABLE_NAME = var.published_layout_snapshot_table_name
      GOOGLE_BUSINESS_TABLE_NAME           = var.google_business_table_name
      PHONE_AGENT_TABLE_NAME               = var.phone_agent_table_name
      EVENT_BUS_NAME                       = var.event_bus_name
      ALERT_TOPIC_ARN                      = var.alert_topic_arn
      CONSOLE_APP_URL                      = var.console_app_url
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

# --- the sweep (every 15 minutes) ----------------------------------------------------------

resource "aws_iam_role" "scheduler" {
  name = "${local.function_name}-scheduler"

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
  name = "invoke-tenant-setup"
  role = aws_iam_role.scheduler.id
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Sid      = "InvokeSweep"
      Effect   = "Allow"
      Action   = "lambda:InvokeFunction"
      Resource = aws_lambda_alias.live.arn
    }]
  })
}

resource "aws_scheduler_schedule" "sweep" {
  name                         = "${local.prefix}tenant-setup-sweep"
  group_name                   = "default"
  schedule_expression          = "rate(15 minutes)"
  schedule_expression_timezone = "Europe/Stockholm"

  flexible_time_window {
    mode = "OFF"
  }

  target {
    arn      = aws_lambda_alias.live.arn
    role_arn = aws_iam_role.scheduler.arn
    input    = jsonencode({ setupTask = "sweep" })

    retry_policy {
      maximum_retry_attempts       = 1
      maximum_event_age_in_seconds = 600
    }
  }
}

# --- alarms --------------------------------------------------------------------------------

resource "aws_cloudwatch_metric_alarm" "errors" {
  alarm_name          = "${local.function_name}-errors"
  alarm_description   = "tenant-setup Lambda errors (the Kom igång checklist or its sweep)"
  namespace           = "AWS/Lambda"
  metric_name         = "Errors"
  dimensions          = { FunctionName = aws_lambda_function.fn.function_name }
  statistic           = "Sum"
  period              = 900
  evaluation_periods  = 1
  threshold           = 1
  comparison_operator = "GreaterThanOrEqualToThreshold"
  treat_missing_data  = "notBreaching"
  alarm_actions       = [var.alert_topic_arn]

  tags = {
    Environment = var.environment
  }
}
