# Execution role for the PreSignedURLFn Lambda.
#
# Full s3:* on the MenuImages bucket (bucket + objects), and permission to
# invalidate CloudFront caches after an image is replaced. No CloudFront
# distribution ARNs are managed in Terraform yet, so per explicit request
# the invalidation policy is scoped to Resource = "*" rather than to
# specific distribution ARNs — tighten this once those ARNs are available.

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
  name = "menu-images-full-access"
  role = aws_iam_role.this.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid    = "FullAccessMenuImagesBucket"
        Effect = "Allow"
        Action = "s3:*"
        Resource = [
          "${var.menu_images_bucket_arn}",
          "${var.menu_images_bucket_arn}/*",
        ]
      }
    ]
  })
}

resource "aws_iam_role_policy" "cloudfront_invalidation" {
  name = "cloudfront-create-invalidation"
  role = aws_iam_role.this.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid      = "CreateInvalidationOnBothDistributions"
        Effect   = "Allow"
        Action   = "cloudfront:CreateInvalidation"
        Resource = "*"
      }
    ]
  })
}

# Scoped to exactly this function's own log group — not logs:* on everything.
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
