
data "aws_caller_identity" "current" {}

locals {
  function_name = var.environment == "prod" ? "catering-discount-tiers" : "${var.environment}-catering-discount-tiers"
}

resource "aws_iam_role" "this" {
  name = var.environment == "prod" ? "catering-discount-tiers-role" : "${var.environment}-catering-discount-tiers-role"

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

resource "aws_iam_role_policy" "dynamodb" {
  name = "catering-discount-tiers-table"
  role = aws_iam_role.this.id
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid      = "CateringDiscountTiersTableFullAccess"
        Effect   = "Allow"
        Action   = "dynamodb:*"
        Resource = "${var.catering_discount_tiers_table_arn}"
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
