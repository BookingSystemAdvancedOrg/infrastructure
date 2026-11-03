# Guest CRM (feature C, ADR-C, CONTRACTS.md 4, 6.C, 9): one guest profile per
# guest per restaurant, keyed by hashed contact identifiers. Application:
# functions/guest-crm (API, hooks, rebuild job), functions/guest-crm-sync
# (reservation, order and catering-requests streams), shared/features/guest_crm.
#
#   guest-crm        JWT routes C1-C11 (network/api-gateway/guest-crm-routes.tf),
#                    hooks privacy.export/erase, tenant.purge, marketing.segment,
#                    the self-re-invoking rebuild job
#   guest-crm-sync   three stream mappings with filter criteria, SQS DLQ
#
# No new access on existing roles here: the hook callers' invoke grants were
# added in Run 0 (security/iam/feature-hooks).

data "aws_caller_identity" "current" {}

locals {
  prefix  = var.environment == "prod" ? "" : "${var.environment}-"
  account = data.aws_caller_identity.current.account_id

  common_env = {
    ENVIRONMENT            = var.environment
    GUEST_CRM_TABLE_NAME   = aws_dynamodb_table.this.name
    TENANT_TABLE_NAME      = var.tenant_table_name
    LOCATION_TABLE_NAME    = var.location_table_name
    LOCATION_ID_INDEX_NAME = var.location_id_index_name
    RESERVATION_TABLE_NAME = var.source_tables["reservation"].name
    ORDER_TABLE_NAME       = var.source_tables["order"].name
    CATERING_TABLE_NAME    = var.source_tables["catering"].name
    EVENT_BUS_NAME         = var.event_bus_name
  }

  functions = {
    guest-crm = {
      timeout = 300 # API calls answer in seconds; the rebuild job uses the rest and re-invokes itself
      memory  = 512
      env = merge(local.common_env, {
        USER_TABLE_NAME      = var.user_table_name
        CONSENT_TABLE_NAME   = var.consent_table_name
        MARKETING_TABLE_NAME = var.marketing_table_name
      })
    }
    guest-crm-sync = {
      timeout = 60
      memory  = 256
      env     = local.common_env
    }
  }

  table_arn   = aws_dynamodb_table.this.arn
  source_arns = [for t in values(var.source_tables) : t.arn]

  statements = {
    guest-crm = [
      {
        Sid      = "GuestCrmTable"
        Effect   = "Allow"
        Action   = ["dynamodb:GetItem", "dynamodb:PutItem", "dynamodb:UpdateItem", "dynamodb:DeleteItem", "dynamodb:Query", "dynamodb:BatchWriteItem"]
        Resource = [local.table_arn, "${local.table_arn}/index/byLastSeen"]
      },
      {
        # C3 reads the contact live from the newest source row; the rebuild
        # walks each location's rows by key (Query, never Scan).
        Sid      = "ReadSourceRows"
        Effect   = "Allow"
        Action   = ["dynamodb:GetItem", "dynamodb:Query"]
        Resource = local.source_arns
      },
      {
        Sid      = "ReadConsentLog"
        Effect   = "Allow"
        Action   = ["dynamodb:Query"]
        Resource = var.consent_table_arn
      },
      {
        Sid      = "ReadMarketingSubscribers"
        Effect   = "Allow"
        Action   = ["dynamodb:GetItem"]
        Resource = var.marketing_table_arn
      },
      {
        Sid       = "PublishGuestCrmEvents"
        Effect    = "Allow"
        Action    = ["events:PutEvents"]
        Resource  = var.event_bus_arn
        Condition = { StringEquals = { "events:source" = "booqy.guest-crm" } }
      },
      {
        # The rebuild job continues itself before its time runs out.
        Sid      = "ReinvokeSelfForRebuild"
        Effect   = "Allow"
        Action   = ["lambda:InvokeFunction"]
        Resource = ["arn:aws:lambda:${var.region}:${local.account}:function:${local.prefix}guest-crm", "arn:aws:lambda:${var.region}:${local.account}:function:${local.prefix}guest-crm:*"]
      },
    ]
    guest-crm-sync = [
      {
        Sid      = "GuestCrmTable"
        Effect   = "Allow"
        Action   = ["dynamodb:GetItem", "dynamodb:PutItem", "dynamodb:UpdateItem", "dynamodb:DeleteItem", "dynamodb:Query"]
        Resource = local.table_arn
      },
      {
        Sid      = "ReadSourceStreams"
        Effect   = "Allow"
        Action   = ["dynamodb:DescribeStream", "dynamodb:GetRecords", "dynamodb:GetShardIterator", "dynamodb:ListStreams"]
        Resource = [for t in values(var.source_tables) : t.stream_arn]
      },
      {
        Sid      = "FailedBatchesToDlq"
        Effect   = "Allow"
        Action   = ["sqs:SendMessage"]
        Resource = aws_sqs_queue.sync_dlq.arn
      },
      {
        Sid       = "PublishGuestVisits"
        Effect    = "Allow"
        Action    = ["events:PutEvents"]
        Resource  = var.event_bus_arn
        Condition = { StringEquals = { "events:source" = "booqy.guest-crm" } }
      },
    ]
  }

  # Only the changes the sync counts (ADR-C 3); everything else never invokes it.
  # Each list is OR-ed (one filter each) and mirrors shared/features/guest_crm
  # classify(), the same test the backfill applies: an order counts when paid
  # or completed, a catering request when confirmed/delivered/closed or paid.
  stream_filters = {
    reservation = [{ status = { S = ["arrived", "no_show", "no_show_charged", "no_show_charge_failed"] } }]
    order       = [{ paymentStatus = { S = ["paid"] } }, { status = { S = ["completed"] } }]
    catering    = [{ status = { S = ["confirmed", "delivered", "closed"] } }, { paid = { BOOL = [true] } }]
  }
}

# --- table -----------------------------------------------------------------------------

resource "aws_dynamodb_table" "this" {
  name         = "${local.prefix}guest-crm"
  billing_mode = "PAY_PER_REQUEST"
  hash_key     = "PK"
  range_key    = "SK"

  # TENANT#<t> / IDENT#, PROFILE#, HIST#, SEGMENT#, EXPORT#, BACKFILL (CONTRACTS.md 4)
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

  # Sparse: profiles only (TENANT#<t>#GUESTS, <lastSeenAt>#<guestId>)
  global_secondary_index {
    name            = "byLastSeen"
    hash_key        = "GSI1PK"
    range_key       = "GSI1SK"
    projection_type = "ALL"
  }

  # Profiles 24 months after last activity, history by source retention, exports 90 days.
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

resource "aws_lambda_alias" "live" {
  for_each         = local.functions
  name             = "live"
  function_name    = aws_lambda_function.fn[each.key].function_name
  function_version = aws_lambda_function.fn[each.key].version

  lifecycle {
    ignore_changes = [function_version, routing_config]
  }
}

# The rebuild job invokes itself asynchronously through the live alias
# (app.py _invoke_self -> "<name>:live"), so this config on that alias applies:
# no automatic retry (a lost run is taken over by a new rebuild once its
# cursor has not been saved for 30 minutes; every row applies once).
resource "aws_lambda_function_event_invoke_config" "api" {
  function_name                = aws_lambda_function.fn["guest-crm"].function_name
  qualifier                    = aws_lambda_alias.live["guest-crm"].name
  maximum_retry_attempts       = 0
  maximum_event_age_in_seconds = 900
}

# --- streams -----------------------------------------------------------------------------

resource "aws_sqs_queue" "sync_dlq" {
  name                      = "${local.prefix}guest-crm-sync-dlq"
  message_retention_seconds = 1209600
  sqs_managed_sse_enabled   = true

  tags = {
    Environment = var.environment
  }
}

resource "aws_lambda_event_source_mapping" "source" {
  for_each = var.source_tables

  event_source_arn               = each.value.stream_arn
  function_name                  = aws_lambda_alias.live["guest-crm-sync"].arn
  starting_position              = "LATEST"
  batch_size                     = 25
  maximum_retry_attempts         = 5
  bisect_batch_on_function_error = true
  function_response_types        = ["ReportBatchItemFailures"]

  destination_config {
    on_failure {
      destination_arn = aws_sqs_queue.sync_dlq.arn
    }
  }

  filter_criteria {
    dynamic "filter" {
      for_each = local.stream_filters[each.key]
      content {
        pattern = jsonencode({
          eventName = ["INSERT", "MODIFY"]
          dynamodb  = { NewImage = filter.value }
        })
      }
    }
  }

  depends_on = [aws_iam_role_policy.fn]
}

# --- alarms ------------------------------------------------------------------------------

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

# guest-crm-sync reads three source streams (reservation, order, catering)
# through the three mappings above. Lambda reports IteratorAge per function,
# not per mapping, so one alarm on the Maximum covers all three: any stream
# 5 minutes behind means throttled GetRecords (shared streams) or failing batches.
resource "aws_cloudwatch_metric_alarm" "sync_iterator_age" {
  alarm_name        = "${local.prefix}guest-crm-sync-iterator-age"
  alarm_description = "guest-crm-sync is more than 5 minutes behind a source stream (reservation, order or catering): GetRecords throttling on a shared stream, or failing batches. Guest counts lag."
  namespace         = "AWS/Lambda"
  metric_name       = "IteratorAge"
  dimensions        = { FunctionName = aws_lambda_function.fn["guest-crm-sync"].function_name }

  statistic           = "Maximum"
  period              = 60
  evaluation_periods  = 5
  comparison_operator = "GreaterThanThreshold"
  threshold           = 300000
  treat_missing_data  = "notBreaching"

  alarm_actions = [var.alert_topic_arn]
  ok_actions    = [var.alert_topic_arn]

  tags = {
    Environment = var.environment
  }
}

resource "aws_cloudwatch_metric_alarm" "dlq" {
  alarm_name          = "${local.prefix}guest-crm-sync-dlq"
  alarm_description   = "Stream batches guest-crm-sync could not apply"
  namespace           = "AWS/SQS"
  metric_name         = "ApproximateNumberOfMessagesVisible"
  dimensions          = { QueueName = aws_sqs_queue.sync_dlq.name }
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
