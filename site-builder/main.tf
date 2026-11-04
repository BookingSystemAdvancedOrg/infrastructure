# Site builder B1 (feature B, ADR-B, CONTRACTS.md 4, 6.B, 7): draft, immutable
# versions, published pointer; publish = validate + contrast + pre-render to
# S3 + pointer swap; one-click rollback. Application: functions/site-builder
# (API B1-B8, Validate/Promote/MarkFailed tasks, tenant.purge) and the Node
# render Lambda built from customer-front-end render-lambda/.
#
# Tenant scoping of S3 keys is in code (keys built from the JWT tenant or the
# workflow input the API wrote). The sites bucket's deploy roles, the
# deploy_boundary and the OIDC roles are NOT changed.

data "aws_caller_identity" "current" {}

locals {
  prefix  = var.environment == "prod" ? "" : "${var.environment}-"
  account = data.aws_caller_identity.current.account_id

  bucket_arn         = "arn:aws:s3:::${var.sites_bucket_name}"
  state_machine_name = "${local.prefix}site-builder-publish"
  state_machine_arn  = "arn:aws:states:${var.region}:${local.account}:stateMachine:${local.state_machine_name}"
  table_arn          = aws_dynamodb_table.this.arn

  functions = {
    site-builder = {
      timeout = 60
      memory  = 512
      env = {
        ENVIRONMENT               = var.environment
        SITE_BUILDER_TABLE_NAME   = aws_dynamodb_table.this.name
        TENANT_TABLE_NAME         = var.tenant_table_name
        LOCATION_TABLE_NAME       = var.location_table_name
        LOCATION_ID_INDEX_NAME    = var.location_id_index_name
        SITES_BUCKET_NAME         = var.sites_bucket_name
        PUBLISH_STATE_MACHINE_ARN = local.state_machine_arn
        SITE_BASE_DOMAIN          = var.site_domain
        EVENT_BUS_NAME            = var.event_bus_name
        REQUEST_GUARD_TABLE_NAME  = var.request_guard_table_name
      }
    }
    site-builder-render = {
      timeout = 120
      memory  = 1024
      env = {
        ENVIRONMENT             = var.environment
        SITE_BUILDER_TABLE_NAME = aws_dynamodb_table.this.name
        SITES_BUCKET_NAME       = var.sites_bucket_name
        # imageKey starts with menu-images/; without a base the rendered pages have no images.
        MENU_IMAGE_BASE_URL = var.menu_image_base_url
        # The API base URL is baked into the render image at build time (site-kit's
        # own build env); passing the stage URL here would be a dependency cycle
        # (stage -> throttled public route B8 -> this module's alias).
      }
    }
  }

  statements = {
    site-builder = [
      {
        Sid      = "SiteBuilderTable"
        Effect   = "Allow"
        Action   = ["dynamodb:GetItem", "dynamodb:PutItem", "dynamodb:UpdateItem", "dynamodb:DeleteItem", "dynamodb:Query", "dynamodb:BatchWriteItem"]
        Resource = local.table_arn
      },
      {
        # Promote copies pages to the root and deletes pages no longer published.
        Sid      = "SitesObjects"
        Effect   = "Allow"
        Action   = ["s3:GetObject", "s3:PutObject", "s3:DeleteObject"]
        Resource = "${local.bucket_arn}/sites/*"
      },
      {
        Sid       = "ListSites"
        Effect    = "Allow"
        Action    = ["s3:ListBucket"]
        Resource  = local.bucket_arn
        Condition = { StringLike = { "s3:prefix" = ["sites/*"] } }
      },
      {
        # The one attribute this feature writes on an existing row (CONTRACTS.md 4):
        # PROFILE.site = {mode, version}, read by tenant-site-config.
        Sid      = "MirrorSiteOnTenantProfile"
        Effect   = "Allow"
        Action   = ["dynamodb:UpdateItem"]
        Resource = var.tenant_table_arn
        Condition = {
          "ForAllValues:StringEquals" = { "dynamodb:Attributes" = ["PK", "SK", "site"] }
          StringEquals                = { "dynamodb:ReturnValues" = ["NONE"] }
        }
      },
      {
        Sid      = "StartPublishWorkflow"
        Effect   = "Allow"
        Action   = ["states:StartExecution"]
        Resource = local.state_machine_arn
      },
      {
        Sid      = "CountPreviewReads"
        Effect   = "Allow"
        Action   = ["dynamodb:UpdateItem"]
        Resource = var.request_guard_table_arn
      },
      {
        Sid       = "PublishSiteBuilderEvents"
        Effect    = "Allow"
        Action    = ["events:PutEvents"]
        Resource  = var.event_bus_arn
        Condition = { StringEquals = { "events:source" = "booqy.site-builder" } }
      },
    ]
    site-builder-render = [
      {
        Sid      = "ReadVersion"
        Effect   = "Allow"
        Action   = ["dynamodb:GetItem"]
        Resource = local.table_arn
      },
      {
        # Writes only under sites/<t>/v/<n>/ (enforced in code; the version key
        # comes from the workflow input the API wrote).
        Sid      = "WriteRenderedVersion"
        Effect   = "Allow"
        Action   = ["s3:PutObject"]
        Resource = "${local.bucket_arn}/sites/*/v/*"
      },
    ]
  }
}

# --- table -------------------------------------------------------------------------------

resource "aws_dynamodb_table" "this" {
  name         = "${local.prefix}site-builder"
  billing_mode = "PAY_PER_REQUEST"
  hash_key     = "PK"
  range_key    = "SK"

  # TENANT#<t> / SITE, DRAFT, VERSION#<n:06d>, PUBLISHED, PUBLISH#, PREVIEW#, AIUSE#, AIPROP#, CUSTOM# (CONTRACTS.md 4)
  attribute {
    name = "PK"
    type = "S"
  }

  attribute {
    name = "SK"
    type = "S"
  }

  # PUBLISH 90 days, PREVIEW 7 days.
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
  name = "${local.prefix}site-builder-publish-role"

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
  name = "invoke-site-builder-tasks"
  role = aws_iam_role.workflow.id
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid      = "RunTasks"
        Effect   = "Allow"
        Action   = ["lambda:InvokeFunction"]
        Resource = [aws_lambda_alias.live["site-builder"].arn, aws_lambda_alias.live["site-builder-render"].arn]
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
    api_alias_arn    = aws_lambda_alias.live["site-builder"].arn
    render_alias_arn = aws_lambda_alias.live["site-builder-render"].arn
    retry = jsonencode({
      ErrorEquals     = ["Lambda.ServiceException", "Lambda.AWSLambdaException", "Lambda.SdkClientException", "Lambda.TooManyRequestsException", "States.Timeout", "RuntimeError"]
      IntervalSeconds = 3
      MaxAttempts     = 4
      BackoffRate     = 2
      JitterStrategy  = "FULL"
    })
  })

  logging_configuration {
    log_destination        = "${aws_cloudwatch_log_group.workflow.arn}:*"
    include_execution_data = false
    level                  = "ERROR"
  }

  tags = {
    Environment = var.environment
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
  alarm_description   = "Site publishes that failed"
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
