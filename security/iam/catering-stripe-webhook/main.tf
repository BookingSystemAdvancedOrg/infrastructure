# Execution role for the CateringStripeWebhookFn Lambda - receives the
# catering Stripe endpoint's events (payments/stripe). Kept separate from
# webhook-payment-intent so a catering bug can't affect food-order payments.
#
#   checkout.session.*   private customer paid -> "confirmed"
#   invoice.*            mirror invoiceStatus; on invoice.finalized copy the
#                        invoice PDF into the documents archive
#   credit_note.created, charge.refunded   record the refund/credit
#
# Deduplication needs no table of its own: the audit entry is written as
# AUDIT#STRIPE#<evt id> with attribute_not_exists(SK) - a redelivered event
# fails that condition and the handler stops. Status updates are
# conditional on status + version, and archived PDFs use fixed keys, so a
# repeat is harmless anyway.

data "aws_caller_identity" "current" {}

locals {
  function_name = var.environment == "prod" ? "catering-stripe-webhook" : "${var.environment}-catering-stripe-webhook"
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
        Sid    = "ArchiveInvoicePdf"
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
        Sid    = "ReadStripeKey"
        Effect = "Allow"
        Action = [
          "secretsmanager:GetSecretValue",
        ]
        Resource = "${var.stripe_secret_arn}"
      }
    ]
  })
}

# Reads this endpoint's Stripe signing secret from Secrets Manager (written
# there by payments/stripe) - only this one secret.
resource "aws_iam_role_policy" "webhook_secret" {
  name = "stripe-webhook-secret-read"
  role = aws_iam_role.this.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid      = "ReadStripeWebhookSigningSecret"
        Effect   = "Allow"
        Action   = "secretsmanager:GetSecretValue"
        Resource = "${var.webhook_secret_arn}"
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
