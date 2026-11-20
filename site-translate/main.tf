# Site languages: POST /translate (Swedish to en, es, ar, fa with Amazon
# Translate) for every restaurant site, reached as /api/translate through the
# site's CloudFront and AWS WAF. One shared cache table, keyed by a hash of the
# protected Swedish text, so each string is translated once across all sites.
# Application: functions/site-translate, shared/site_translate.
# Spec: scratchpad site-lang/SPEC.md sections 1.1 to 1.9.

data "aws_caller_identity" "current" {}

locals {
  prefix        = var.environment == "prod" ? "" : "${var.environment}-"
  account       = data.aws_caller_identity.current.account_id
  function_name = "${local.prefix}site-translate"
  # Daily characters that trigger the early warning: 80% of 1/30 of the global budget.
  daily_chars_warning = floor(var.global_chars_per_30d / 30 * 0.8)
  terminology_name    = "${local.prefix}site-translate-terms"
  terminology_file    = "${path.module}/terminology.csv"
}

# --- custom terminology ----------------------------------------------------------------------

# Booqy's restaurant words for Amazon Translate (terminology.csv: sv source,
# en, es, ar, fa targets): bord is a restaurant table, platser are seats,
# sällskap is a party, ... In whole sentences Translate otherwise picked
# "spreadsheet table" and "web sites". The function passes it as
# TerminologyNames on every TranslateText call.
#
# No Terraform resource exists for a terminology, so CI imports it with the
# AWS CLI on apply (needs translate:ImportTerminology, which the CI role has).
# ImportTerminology with OVERWRITE is idempotent; the import runs again only
# when the CSV (its hash) or the name changes. No destroy step: deleting it on
# a replace would break translations until the new import, and a leftover
# terminology costs nothing (delete it by hand if the module is ever removed).
resource "terraform_data" "terminology" {
  input = {
    name = local.terminology_name
    hash = filesha256(local.terminology_file)
  }
  triggers_replace = [local.terminology_name, filesha256(local.terminology_file)]

  provisioner "local-exec" {
    interpreter = ["bash", "-c"]
    environment = {
      R    = var.region
      NAME = self.input.name
      FILE = abspath(local.terminology_file)
    }
    command = <<-EOT
      set -euo pipefail
      aws translate import-terminology --region "$R" --name "$NAME" --merge-strategy OVERWRITE \
        --description "Booqy restaurant terms for the site languages (sv to en, es, ar, fa)" \
        --data-file "fileb://$FILE" --terminology-data "Format=CSV,Directionality=UNI" \
        --query "TerminologyProperties.[Name,TermCount]" --output text
    EOT
  }
}

# --- cache table ---------------------------------------------------------------------------

# PK = T#<lang>#<sha256 of the protected source>; attributes text, ttl (180 days,
# refreshed by the function). A cache: no PITR, no deletion protection.
resource "aws_dynamodb_table" "cache" {
  name         = "${local.prefix}site-translations"
  billing_mode = "PAY_PER_REQUEST"
  hash_key     = "PK"

  attribute {
    name = "PK"
    type = "S"
  }

  ttl {
    attribute_name = "ttl"
    enabled        = true
  }

  point_in_time_recovery {
    enabled = false
  }

  server_side_encryption {
    enabled = true
  }

  deletion_protection_enabled = false

  tags = {
    Environment = var.environment
  }
}

# --- function ------------------------------------------------------------------------------

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
  name = "site-translate-access"
  role = aws_iam_role.fn.id
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        # TranslateText with or without the terminology (no extra action is
        # needed to use one; "*" covers the terminology ARN).
        Sid      = "TranslateText"
        Effect   = "Allow"
        Action   = ["translate:TranslateText"]
        Resource = "*"
      },
      {
        Sid      = "TranslationCache"
        Effect   = "Allow"
        Action   = ["dynamodb:BatchGetItem", "dynamodb:BatchWriteItem", "dynamodb:GetItem", "dynamodb:PutItem", "dynamodb:UpdateItem"]
        Resource = aws_dynamodb_table.cache.arn
      },
      {
        # Per-IP, per-restaurant and platform request and character counters.
        Sid      = "Budgets"
        Effect   = "Allow"
        Action   = ["dynamodb:UpdateItem"]
        Resource = var.request_guard_table_arn
      },
      {
        # Which restaurant owns the viewer host (DOMAIN# and SLUG# rows).
        Sid      = "ResolveSite"
        Effect   = "Allow"
        Action   = ["dynamodb:GetItem"]
        Resource = var.tenant_table_arn
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
  function_name                  = local.function_name
  role                           = aws_iam_role.fn.arn
  package_type                   = "Image"
  image_uri                      = "${var.ecr_repository_url}:latest"
  publish                        = true
  architectures                  = ["arm64"]
  timeout                        = 28
  memory_size                    = 512
  reserved_concurrent_executions = var.reserved_concurrency

  lifecycle {
    ignore_changes = [image_uri]
  }

  environment {
    variables = {
      ENVIRONMENT                         = var.environment
      TRANSLATION_TABLE_NAME              = aws_dynamodb_table.cache.name
      TENANT_TABLE_NAME                   = var.tenant_table_name
      REQUEST_GUARD_TABLE_NAME            = var.request_guard_table_name
      SITE_WAF_SECRET                     = var.site_waf_secret
      CLOUDFRONT_EDGE_SECRET              = var.cloudfront_edge_secret
      SITE_TRANSLATE_IP_REQUESTS_PER_5MIN = tostring(var.ip_requests_per_5min)
      SITE_TRANSLATE_IP_CHARS_PER_HOUR    = tostring(var.ip_chars_per_hour)
      SITE_TRANSLATE_TENANT_CHARS_PER_30D = tostring(var.tenant_chars_per_30d)
      SITE_TRANSLATE_GLOBAL_CHARS_PER_30D = tostring(var.global_chars_per_30d)
      # From terraform_data.terminology, so the function changes only after the import.
      SITE_TRANSLATE_TERMINOLOGY      = terraform_data.terminology.output.name
      SITE_TRANSLATE_TERMINOLOGY_HASH = substr(terraform_data.terminology.output.hash, 0, 16)
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
  alarm_description   = "site-translate Lambda errors"
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

# The function emits these as CloudWatch EMF metrics with no dimensions
# (namespace Booqy/SiteTranslate).
resource "aws_cloudwatch_metric_alarm" "chars_high" {
  alarm_name          = "${local.function_name}-translated-chars-high"
  alarm_description   = "site-translate billed characters per day above 80% of the daily share of the platform 30-day budget on 2 of 3 days"
  namespace           = "Booqy/SiteTranslate"
  metric_name         = "TranslatedChars"
  statistic           = "Sum"
  period              = 86400
  evaluation_periods  = 3
  datapoints_to_alarm = 2
  threshold           = local.daily_chars_warning
  comparison_operator = "GreaterThanThreshold"
  treat_missing_data  = "notBreaching"
  alarm_actions       = [var.alert_topic_arn]

  tags = {
    Environment = var.environment
  }
}

resource "aws_cloudwatch_metric_alarm" "budget_limited" {
  alarm_name          = "${local.function_name}-budget-limited"
  alarm_description   = "site-translate hit a character budget: strings stay Swedish for some guests"
  namespace           = "Booqy/SiteTranslate"
  metric_name         = "BudgetLimited"
  statistic           = "Sum"
  period              = 3600
  evaluation_periods  = 1
  threshold           = 1
  comparison_operator = "GreaterThanOrEqualToThreshold"
  treat_missing_data  = "notBreaching"
  alarm_actions       = [var.alert_topic_arn]

  tags = {
    Environment = var.environment
  }
}
