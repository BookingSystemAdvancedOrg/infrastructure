# Execution role for the tenant-purge Lambda: deletes an offboarded
# restaurant's data once its retention period is over (see the function's
# docstring in the application repo, functions/tenant-purge/app.py).
#
# This role can delete any tenant's rows - DynamoDB has no way to scope a
# role to "tenants whose status is offboarded" - so the Lambda checks the
# status and purgeAt itself, and nothing but its schedule (and its own
# continuation) can invoke it. Item-level actions only: no table, bucket,
# pool or zone can be deleted or reconfigured with it.
#
# Not here, on purpose: the catering documents bucket (7-year Object Lock),
# Stripe, and the platform's own hosted zones (explicit Deny below).

data "aws_caller_identity" "current" {}

locals {
  function_name = var.environment == "prod" ? "tenant-purge" : "${var.environment}-tenant-purge"
  function_arn  = "arn:aws:lambda:${var.region}:${data.aws_caller_identity.current.account_id}:function:${local.function_name}"
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

resource "aws_iam_role_policy" "data" {
  name = "delete-tenant-data"
  role = aws_iam_role.this.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        # Lists tenants (GSI1), reads/writes the PROFILE (purgeAt, tombstone),
        # deletes the tenant's own rows and released domain claims.
        Sid    = "TenantTable"
        Effect = "Allow"
        Action = [
          "dynamodb:GetItem",
          "dynamodb:Query",
          "dynamodb:PutItem",
          "dynamodb:UpdateItem",
          "dynamodb:DeleteItem",
          "dynamodb:BatchWriteItem",
        ]
        Resource = [var.tenant_table_arn, "${var.tenant_table_arn}/index/*"]
      },
      {
        Sid    = "DeleteTenantPartitions"
        Effect = "Allow"
        Action = [
          "dynamodb:Query",
          "dynamodb:DeleteItem",
          "dynamodb:BatchWriteItem",
        ]
        Resource = concat(var.data_table_arns, [var.user_table_arn])
      },
      {
        Sid      = "FindTenantUsers"
        Effect   = "Allow"
        Action   = "dynamodb:Query"
        Resource = "${var.user_table_arn}/index/${var.user_tenant_index_name}"
      },
      {
        Sid      = "DeleteTenantUsers"
        Effect   = "Allow"
        Action   = "cognito-idp:AdminDeleteUser"
        Resource = var.tenant_user_pool_arn
      },
      {
        Sid      = "ListMenuImages"
        Effect   = "Allow"
        Action   = "s3:ListBucket"
        Resource = var.menu_image_bucket_arn
        Condition = {
          StringLike = { "s3:prefix" = ["menu-images/*"] }
        }
      },
      {
        Sid      = "DeleteMenuImages"
        Effect   = "Allow"
        Action   = "s3:DeleteObject"
        Resource = "${var.menu_image_bucket_arn}/menu-images/*"
      },
      {
        Sid      = "NotifyOperators"
        Effect   = "Allow"
        Action   = "sns:Publish"
        Resource = var.alert_topic_arn
      },
      {
        # Carries on in a new invocation when a run gets close to its timeout.
        Sid      = "ContinueItself"
        Effect   = "Allow"
        Action   = "lambda:InvokeFunction"
        Resource = [local.function_arn, "${local.function_arn}:*"]
      },
    ]
  })
}

# Domains we ran DNS for: switch auto-renew off for domains registered
# through us, and delete a hosted zone the domain no longer points at.
resource "aws_iam_role_policy" "domains" {
  name = "release-tenant-domains"
  role = aws_iam_role.this.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = concat([
      {
        # Route 53 Domains has no resource-level permissions.
        Sid      = "AutoRenewOff"
        Effect   = "Allow"
        Action   = "route53domains:DisableDomainAutoRenew"
        Resource = "*"
      },
      {
        Sid    = "DeleteRestaurantZones"
        Effect = "Allow"
        Action = [
          "route53:GetHostedZone",
          "route53:ListResourceRecordSets",
          "route53:ChangeResourceRecordSets",
          "route53:DeleteHostedZone",
        ]
        Resource = "arn:aws:route53:::hostedzone/*"
      },
      ], length(var.protected_zone_ids) == 0 ? [] : [
      {
        Sid      = "NeverThePlatformZones"
        Effect   = "Deny"
        Action   = ["route53:ChangeResourceRecordSets", "route53:DeleteHostedZone"]
        Resource = [for id in var.protected_zone_ids : "arn:aws:route53:::hostedzone/${id}"]
      },
    ])
  })
}

# Scoped to exactly this function's own log group; the log group itself is
# created with the function (compute/lambda/tenant-purge).
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
