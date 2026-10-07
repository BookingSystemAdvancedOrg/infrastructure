# Execution role for the CateringCustomerFn Lambda - the customer's side of
# the workflow, reached through magic links (no account). Every call is
# authenticated by recomputing the link HMAC with the link-signing key.
#
# Starts the BankID signing session with the signing provider and, for
# private customers, a Stripe Checkout Session (also after a failed or
# expired payment - the signature is kept). Hands out presigned GET URLs
# for the offer and signed agreement, which is why it needs s3:GetObject.

data "aws_caller_identity" "current" {}

locals {
  function_name = var.environment == "prod" ? "catering-customer" : "${var.environment}-catering-customer"
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

resource "aws_iam_role_policy" "location" {
  name = "location-table-read"
  role = aws_iam_role.this.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid    = "ReadLocationTable"
        Effect = "Allow"
        Action = [
          "dynamodb:Scan",
          "dynamodb:GetItem",
          "dynamodb:Query",
        ]
        Resource = "${var.location_table_arn}"
      }
    ]
  })
}

resource "aws_iam_role_policy" "documents_read" {
  name = "catering-documents-read"
  role = aws_iam_role.this.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid    = "PresignDocumentDownloads"
        Effect = "Allow"
        Action = [
          "s3:GetObject",
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
        Sid    = "ReadLinkSigningStripeSecrets"
        Effect = "Allow"
        Action = [
          "secretsmanager:GetSecretValue",
        ]
        Resource = [
          "${var.link_signing_key_secret_arn}",
          "${var.signing_provider_secret_arn}",
          "${var.stripe_secret_arn}",
        ]
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
