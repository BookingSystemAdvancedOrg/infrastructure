# Execution role for the CateringOfferFn Lambda - the owner's (JWT-protected)
# side of the catering workflow: view a request with its versions and audit
# log, save an adjusted offer version, send / decline / cancel / mark
# delivered, list invoices and mark a Bankgiro payment as received.
#
# Write access on catering-requests covers the head item AND the
# CAPACITY#<date> items (reserved on send, released on decline/cancel), all
# in one TransactWriteItems call - IAM authorizes each action inside a
# transaction individually, so there is no separate "transact" permission.
# Write access follows the repo convention (dynamodb:* on the table). On
# catering-request-history that does NOT make history editable: the
# table's resource policy explicitly denies UpdateItem/DeleteItem to every
# principal, and an explicit Deny always wins over this Allow - so in
# practice the history is still append-only.

data "aws_caller_identity" "current" {}

locals {
  function_name = var.environment == "prod" ? "catering-offer" : "${var.environment}-catering-offer"
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

resource "aws_iam_role_policy" "menu" {
  name = "menu-table-read"
  role = aws_iam_role.this.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid    = "ReadMenuTable"
        Effect = "Allow"
        Action = [
          "dynamodb:Scan",
          "dynamodb:GetItem",
          "dynamodb:Query",
        ]
        Resource = "${var.menu_table_arn}"
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

resource "aws_iam_role_policy" "invoke_document" {
  name = "invoke-catering-document"
  role = aws_iam_role.this.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid    = "RenderOfferPdf"
        Effect = "Allow"
        Action = [
          "lambda:InvokeFunction",
        ]
        Resource = "${var.document_function_arn}"
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
