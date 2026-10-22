# Kitchen printing (issue 2): paid orders print on the restaurant's Star
# CloudPRNT printer (mC-Print3), which polls our API over HTTPS. Nothing runs
# on site and printing never sits in the order request path.
# Application side: functions/print-jobs, functions/print-device,
# shared/printing.py (jobs, devices, state machine), shared/print_ticket.py
# (StarPRNT ticket).
#
# Everything the feature owns lives in this module except the table
# (storage/dynamodb/print), the ECR repositories (top-level modules, CI
# bootstraps images from them) and the API routes
# (network/api-gateway/printing-routes.tf).
#
#   print-jobs    order stream (paid -> auto job, cancelled -> "MAKULERAD"),
#                 sweep every 5 minutes (stuck/failed metrics), admin API
#                 /locations/{locationId}/print[/...] (JWT)
#   print-device  the printer: POST|GET|DELETE /print/cloudprnt/{deviceId}
#                 (no JWT; HTTP Basic with the device's own secret)

data "aws_caller_identity" "current" {}

locals {
  prefix  = var.environment == "prod" ? "" : "${var.environment}-"
  account = data.aws_caller_identity.current.account_id

  tenant_env = {
    ENVIRONMENT            = var.environment
    TENANT_TABLE_NAME      = var.tenant_table_name
    LOCATION_TABLE_NAME    = var.location_table_name
    LOCATION_ID_INDEX_NAME = var.location_id_index_name
    ORDER_TABLE_NAME       = var.order_table_name
    PRINT_TABLE_NAME       = var.print_table_name
  }

  functions = {
    print-jobs = {
      timeout = 60
      memory  = 256
      env = merge(local.tenant_env, {
        USER_TABLE_NAME  = var.user_table_name
        PRINT_SERVER_URL = var.print_server_url
      })
    }
    print-device = {
      timeout = 10
      memory  = 256
      env = merge(local.tenant_env, {
        REQUEST_GUARD_TABLE_NAME = var.request_guard_table_name
      })
    }
  }

  # Least privilege per function. Tenant/location reads (and the staff
  # location check for print-jobs) come from the shared tenant-context
  # policy (config.tf tenant_aware_role_names, staff_check_role_names).
  statements = {
    print-jobs = [
      {
        Sid      = "PrintTable"
        Effect   = "Allow"
        Action   = ["dynamodb:GetItem", "dynamodb:PutItem", "dynamodb:UpdateItem", "dynamodb:DeleteItem", "dynamodb:Query"]
        Resource = var.print_table_arn
      },
      {
        # Admin banner (Query per location) and the sweep (Scan of the
        # sparse index of open jobs).
        Sid      = "PrintQueue"
        Effect   = "Allow"
        Action   = ["dynamodb:Query", "dynamodb:Scan"]
        Resource = "${var.print_table_arn}/index/queue"
      },
      {
        # "Skriv ut igen" checks the order exists and belongs to the location.
        Sid      = "ReadOrders"
        Effect   = "Allow"
        Action   = ["dynamodb:GetItem"]
        Resource = var.order_table_arn
      },
      {
        Sid      = "ReadOrderStream"
        Effect   = "Allow"
        Action   = ["dynamodb:DescribeStream", "dynamodb:GetRecords", "dynamodb:GetShardIterator", "dynamodb:ListStreams"]
        Resource = var.order_stream_arn
      },
      {
        Sid      = "FailedStreamBatchesToDlq"
        Effect   = "Allow"
        Action   = ["sqs:SendMessage"]
        Resource = var.print_stream_dlq_arn
      },
    ]

    print-device = [
      {
        # Device lookup, lastSeenAt/MAC, job lease and confirmation. No
        # Put/Delete: devices and jobs are created and removed by print-jobs.
        Sid      = "PrintTable"
        Effect   = "Allow"
        Action   = ["dynamodb:GetItem", "dynamodb:UpdateItem"]
        Resource = var.print_table_arn
      },
      {
        Sid      = "PrintIndexes"
        Effect   = "Allow"
        Action   = ["dynamodb:Query"]
        Resource = ["${var.print_table_arn}/index/queue", "${var.print_table_arn}/index/byDevice"]
      },
      {
        # The ticket is rendered from the order when the printer fetches it.
        Sid      = "ReadOrders"
        Effect   = "Allow"
        Action   = ["dynamodb:GetItem"]
        Resource = var.order_table_arn
      },
      {
        # Failed device logins per IP address (shared/request_guard.py).
        Sid      = "CountFailedLogins"
        Effect   = "Allow"
        Action   = ["dynamodb:UpdateItem"]
        Resource = var.request_guard_table_arn
      },
    ]
  }
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

# --- order stream: paid -> auto job, cancelled -> cancellation slip --------------------------

# The third consumer of the order stream (after notification and
# marketing-sync). AWS advises at most two readers per shard; a third adds
# GetRecords throttling risk, watched by the IteratorAge alarm below.
# Filtered here so print-jobs only runs for the two transitions it acts on.
# A batch that keeps failing goes to the print-stream DLQ, which dlq-replay
# redelivers; the job's conditional put makes redelivery safe.
resource "aws_lambda_event_source_mapping" "orders" {
  event_source_arn               = var.order_stream_arn
  function_name                  = aws_lambda_alias.live["print-jobs"].arn
  starting_position              = "LATEST"
  batch_size                     = 10
  maximum_retry_attempts         = 5
  bisect_batch_on_function_error = true
  function_response_types        = ["ReportBatchItemFailures"]

  destination_config {
    on_failure {
      destination_arn = var.print_stream_dlq_arn
    }
  }

  filter_criteria {
    filter {
      pattern = jsonencode({
        eventName = ["MODIFY"]
        dynamodb = {
          OldImage = { status = { S = ["pending_payment"] } }
          NewImage = { status = { S = ["confirmed"] } }
        }
      })
    }
    filter {
      pattern = jsonencode({
        eventName = ["MODIFY"]
        dynamodb = {
          OldImage = { status = { S = [{ "anything-but" = ["cancelled"] }] } }
          NewImage = { status = { S = ["cancelled"] } }
        }
      })
    }
  }

  # Lambda validates stream access when the mapping is created.
  depends_on = [aws_iam_role_policy.fn]
}

# --- sweep every 5 minutes -------------------------------------------------------------------

resource "aws_iam_role" "scheduler" {
  name = "${local.prefix}scheduler-invoke-print-jobs-role"

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
  name = "invoke-print-jobs-function"
  role = aws_iam_role.scheduler.id
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Sid      = "InvokePrintJobs"
      Effect   = "Allow"
      Action   = "lambda:InvokeFunction"
      Resource = [aws_lambda_function.fn["print-jobs"].arn, "${aws_lambda_function.fn["print-jobs"].arn}:*"]
    }]
  })
}

# A failed sweep is simply the next sweep's work.
resource "aws_lambda_function_event_invoke_config" "sweep" {
  function_name                = aws_lambda_function.fn["print-jobs"].function_name
  qualifier                    = aws_lambda_alias.live["print-jobs"].name
  maximum_retry_attempts       = 0
  maximum_event_age_in_seconds = 300
}

resource "aws_scheduler_schedule" "sweep" {
  name                = "${local.prefix}print-jobs-sweep"
  group_name          = "default"
  schedule_expression = "rate(5 minutes)"

  flexible_time_window {
    mode = "OFF"
  }

  target {
    arn      = aws_lambda_alias.live["print-jobs"].arn
    role_arn = aws_iam_role.scheduler.arn
    input    = jsonencode({ source = "sweep" })

    retry_policy {
      maximum_retry_attempts       = 0
      maximum_event_age_in_seconds = 300
    }
  }
}

# --- alarms ----------------------------------------------------------------------------------

# Jobs that have waited for the printer for 15 minutes (three sweeps in a
# row): a printer is off, unplugged or out of paper while orders come in.
# The restaurant sees "Skrivaren svarar inte" in admin; this tells us.
resource "aws_cloudwatch_metric_alarm" "stuck_jobs" {
  alarm_name        = "${local.prefix}print-stuck-jobs"
  alarm_description = "Print jobs have waited more than 5 minutes for the kitchen printer in three sweeps in a row. A restaurant's printer is probably offline: check print-jobs logs (sweep) for the location."
  namespace         = "Booqy/${var.environment}"
  metric_name       = "PrintStuckJobs"

  statistic           = "Maximum"
  period              = 300
  evaluation_periods  = 3
  comparison_operator = "GreaterThanThreshold"
  threshold           = 0
  treat_missing_data  = "notBreaching"

  alarm_actions = [var.alert_topic_arn]
  ok_actions    = [var.alert_topic_arn]

  tags = {
    Environment = var.environment
  }
}

# A job gave up after 5 attempts: a ticket did not print and the kitchen
# has only the admin screen for that order.
resource "aws_cloudwatch_metric_alarm" "failed_jobs" {
  alarm_name        = "${local.prefix}print-failed-jobs"
  alarm_description = "A print job failed after 5 attempts (printer error or never confirmed). The order shows as unprinted in admin: check print-device logs."
  namespace         = "Booqy/${var.environment}"
  metric_name       = "PrintJobFailed"

  statistic           = "Sum"
  period              = 300
  evaluation_periods  = 1
  comparison_operator = "GreaterThanThreshold"
  threshold           = 0
  treat_missing_data  = "notBreaching"

  alarm_actions = [var.alert_topic_arn]

  tags = {
    Environment = var.environment
  }
}

# The order stream has three readers now: tickets lagging two minutes
# behind payments means throttled or failing reads.
resource "aws_cloudwatch_metric_alarm" "stream_iterator_age" {
  alarm_name        = "${local.prefix}print-jobs-iterator-age"
  alarm_description = "print-jobs is more than 2 minutes behind the order stream (three readers on one stream: GetRecords throttling, or failing batches). Paid orders print late."
  namespace         = "AWS/Lambda"
  metric_name       = "IteratorAge"
  dimensions        = { FunctionName = aws_lambda_function.fn["print-jobs"].function_name }

  statistic           = "Maximum"
  period              = 60
  evaluation_periods  = 3
  comparison_operator = "GreaterThanThreshold"
  threshold           = 120000
  treat_missing_data  = "notBreaching"

  alarm_actions = [var.alert_topic_arn]
  ok_actions    = [var.alert_topic_arn]

  tags = {
    Environment = var.environment
  }
}

resource "aws_cloudwatch_metric_alarm" "errors" {
  for_each = local.functions

  alarm_name        = "${local.prefix}${each.key}-errors"
  alarm_description = "${each.key} crashed (Lambda errors; the printer's requests answer 5xx). Check the ${each.key} logs."
  namespace         = "AWS/Lambda"
  metric_name       = "Errors"
  dimensions        = { FunctionName = aws_lambda_function.fn[each.key].function_name }

  statistic           = "Sum"
  period              = 300
  evaluation_periods  = 1
  comparison_operator = "GreaterThanThreshold"
  threshold           = 0
  treat_missing_data  = "notBreaching"

  alarm_actions = [var.alert_topic_arn]

  tags = {
    Environment = var.environment
  }
}
