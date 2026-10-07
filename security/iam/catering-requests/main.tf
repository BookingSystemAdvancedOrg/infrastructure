# Execution role for the CateringRequestsFn Lambda - the public request
# intake (POST, no account) plus the owner's request list (GET, JWT).
#
# On submit it re-prices every line from the menu table and discount tiers
# (never trusting the browser's total), checks the rules in cateringSettings
# on the location item, verifies the Cloudflare Turnstile token, builds the
# customer's magic link with the link-signing key, writes the head item and
# appends the first audit entry to catering-request-history.
#
# catering-requests is limited to the item actions the handler actually
# uses - no Scan, no DeleteItem, no table-level actions - instead of the
# previous dynamodb:*.

data "aws_caller_identity" "current" {}

locals {
  function_name = var.environment == "prod" ? "catering-requests" : "${var.environment}-catering-requests"
}

resource "aws_iam_role" "this" {
  name = var.environment == "prod" ? "catering-requests-role" : "${var.environment}-catering-requests-role"

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
}

resource "aws_iam_role_policy" "dynamodb_catering_requests" {
  name = "catering-requests-table"
  role = aws_iam_role.this.id
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid    = "CateringRequestsItemAccess"
        Effect = "Allow"
        Action = [
          "dynamodb:GetItem",
          "dynamodb:Query",
          "dynamodb:PutItem",
          "dynamodb:UpdateItem",
          "dynamodb:ConditionCheckItem",
        ]
        Resource = "${var.catering_requests_table_arn}"
      }
    ]
  })
}

# Append-only: the first audit entry ("requested") for every submission.
resource "aws_iam_role_policy" "dynamodb_catering_request_history" {
  name = "catering-request-history-append"
  role = aws_iam_role.this.id
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid      = "AppendCateringRequestHistory"
        Effect   = "Allow"
        Action   = "dynamodb:PutItem"
        Resource = "${var.catering_request_history_table_arn}"
      }
    ]
  })
}

resource "aws_iam_role_policy" "dynamodb_location" {
  name = "location-table-read"
  role = aws_iam_role.this.id
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid    = "ReadLocationTable"
        Effect = "Allow"
        Action = [
          "dynamodb:GetItem",
          "dynamodb:Query",
        ]
        Resource = "${var.location_table_arn}"
      }
    ]
  })
}

resource "aws_iam_role_policy" "dynamodb_discount_tiers" {
  name = "catering-discount-tiers-table-read"
  role = aws_iam_role.this.id
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid    = "ReadCateringDiscountTiersTable"
        Effect = "Allow"
        Action = [
          "dynamodb:GetItem",
          "dynamodb:Query",
        ]
        Resource = "${var.catering_discount_tiers_table_arn}"
      }
    ]
  })
}

resource "aws_iam_role_policy" "dynamodb_menu" {
  name = "menu-table-read"
  role = aws_iam_role.this.id
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid    = "ReadMenuTable"
        Effect = "Allow"
        Action = [
          "dynamodb:GetItem",
          "dynamodb:Query",
          "dynamodb:BatchGetItem",
        ]
        Resource = "${var.menu_table_arn}"
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
        Sid    = "ReadTurnstileAndLinkSigningKey"
        Effect = "Allow"
        Action = "secretsmanager:GetSecretValue"
        Resource = [
          "${var.turnstile_secret_arn}",
          "${var.link_signing_key_secret_arn}",
        ]
      }
    ]
  })
}

resource "aws_iam_role_policy" "logs" {
  name = "cloudwatch-logs"
  role = aws_iam_role.this.id
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid    = "WriteLogs"
        Effect = "Allow"
        Action = [
          "logs:CreateLogStream",
          "logs:PutLogEvents"
        ]
        Resource = "arn:aws:logs:${var.region}:${data.aws_caller_identity.current.account_id}:log-group:/aws/lambda/${local.function_name}:*"
      }
    ]
  })
}
