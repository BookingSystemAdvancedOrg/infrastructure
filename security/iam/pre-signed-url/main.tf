# Execution role for the PreSignedURLFn Lambda.
#
# The function only signs PutObject URLs for menu image uploads
# (application functions/pre-signed-url), so that is all it may do: the
# browser's upload runs with this role's permissions. No reads, deletes or
# bucket-level actions, and no CloudFront invalidation (the code doesn't
# invalidate; image keys are unique, so nothing needs it).

data "aws_caller_identity" "current" {}

locals {
  function_name = var.environment == "prod" ? "pre-signed-url" : "${var.environment}-pre-signed-url"
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

resource "aws_iam_role_policy" "s3_full" {
  name = "menu-images-upload"
  role = aws_iam_role.this.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid      = "UploadMenuImages"
        Effect   = "Allow"
        Action   = "s3:PutObject"
        Resource = "${var.menu_images_bucket_arn}/*"
      }
    ]
  })
}


# Scoped to exactly this function's own log group - not logs:* on everything.
#
# No logs:CreateLogGroup - the log group is expected to be provisioned
# explicitly alongside this Lambda's function resource (same pattern as
# compute/lambda/activate-layout-version), with a real retention period
# instead of CloudWatch's "never expire" default. Until that function
# module exists, this role has no way to create its own log group -
# deploying this Lambda without one first means it can't write any logs
# at all.
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
