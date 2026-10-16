
data "aws_caller_identity" "current" {}

locals {
  function_name = var.environment == "prod" ? "catering-settings" : "${var.environment}-catering-settings"
}

resource "aws_iam_role" "this" {
  name = var.environment == "prod" ? "catering-settings-role" : "${var.environment}-catering-settings-role"

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

# Item-level only, replacing the previous dynamodb:* on the whole location
# table: GET reads the cateringSettings map off one location item, PUT
# updates that map with an UpdateExpression (SET cateringSettings = ...).
# No PutItem, so this function can never overwrite a whole location item,
# and no DeleteItem/Scan/table-level actions.
resource "aws_iam_role_policy" "dynamodb" {
  name = "location-table"
  role = aws_iam_role.this.id
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid    = "LocationCateringSettingsAccess"
        Effect = "Allow"
        Action = [
          "dynamodb:GetItem",
          "dynamodb:Query",
          "dynamodb:UpdateItem",
        ]
        Resource = "${var.location_table_arn}"
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
