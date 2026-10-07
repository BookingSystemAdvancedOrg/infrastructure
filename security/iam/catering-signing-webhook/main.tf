# Execution role for the CateringSigningWebhookFn Lambda - receives the
# BankID signing provider's callbacks. Verifies the callback signature with
# the webhook secret, fetches the PAdES-sealed PDF and stores it in the
# documents archive, then moves the request to "signed" (private) or
# "confirmed" (company) with a conditional update on status + version.
#
# Deduplication needs no table of its own: the audit entry is written as
# AUDIT#SIGNING#<provider event id> with attribute_not_exists(SK), so a
# redelivered callback fails that condition and the handler stops there;
# the status update is conditional too.

data "aws_caller_identity" "current" {}

locals {
  function_name = var.environment == "prod" ? "catering-signing-webhook" : "${var.environment}-catering-signing-webhook"
}

resource "aws_iam_role" "this" {
  name = "${local.function_name}-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect    = "Allow"
        Principal = { Service = "lambda.amazonaws.com" }
        Action    = "sts:AssumeRole"
      }
    ]
  })

  tags = {
    Environment = var.environment
  }
}

resource "aws_iam_role_policy" "catering_requests" {
  name = "catering-requests-table-full-access"
  role = aws_iam_role.this.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid      = "FullAccessCateringRequestsTable"
        Effect   = "Allow"
        Action   = "dynamodb:*"
        Resource = "${var.catering_requests_table_arn}"
      }
    ]
  })
}

resource "aws_iam_role_policy" "catering_request_history" {
  name = "catering-request-history-table-full-access"
  role = aws_iam_role.this.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid      = "FullAccessCateringRequestHistoryTable"
        Effect   = "Allow"
        Action   = "dynamodb:*"
        Resource = "${var.catering_request_history_table_arn}"
      }
    ]
  })
}

resource "aws_iam_role_policy" "documents_write" {
  name = "catering-documents-write"
  role = aws_iam_role.this.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid    = "ArchiveSignedAgreement"
        Effect = "Allow"
        Action = [
          "s3:PutObject",
        ]
        Resource = "${var.catering_documents_bucket_arn}/*"
      }
    ]
  })
}

resource "aws_iam_role_policy" "secrets" {
  name = "catering-secrets-read"
  role = aws_iam_role.this.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid    = "ReadSigningProviderSecret"
        Effect = "Allow"
        Action = [
          "secretsmanager:GetSecretValue",
        ]
        Resource = "${var.signing_provider_secret_arn}"
      }
    ]
  })
}

# Scoped to exactly this function's own log group - not logs:* on everything.
# No logs:CreateLogGroup: the log group is provisioned explicitly alongside
# the function (compute/lambda/<name>) with a real retention period.
resource "aws_iam_role_policy" "logs" {
  name = "cloudwatch-logs"
  role = aws_iam_role.this.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid    = "WriteOwnLogGroup"
        Effect = "Allow"
        Action = [
          "logs:CreateLogStream",
          "logs:PutLogEvents",
        ]
        Resource = "arn:aws:logs:${var.region}:${data.aws_caller_identity.current.account_id}:log-group:/aws/lambda/${local.function_name}:*"
      }
    ]
  })
}
