# Role assumed by the operator console repo's (sbs-admin) GitHub Actions
# pipeline via OIDC - no long-lived AWS credentials stored as a repo secret.
# That repo holds both halves of the console, so the role can deploy exactly
# those two things and nothing else:
#   - the web app: sync to its own S3 bucket, invalidate its own distribution
#   - the platform-tenants Lambda: push to its one ECR repo, update that one
#     function's code (UpdateFunctionCode only - not its configuration,
#     environment, role or permissions, which stay Terraform's)
# No access to the customer/admin buckets, other ECR repos or Lambdas.

locals {
  role_name = var.environment == "prod" ? "platform-admin-front-end-deploy-role" : "${var.environment}-platform-admin-front-end-deploy-role"
}

resource "aws_iam_role" "this" {
  name = local.role_name

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect    = "Allow"
        Principal = { Federated = "${var.oidc_provider_arn}" }
        Action    = "sts:AssumeRoleWithWebIdentity"
        Condition = {
          StringEquals = {
            "token.actions.githubusercontent.com:aud" = "sts.amazonaws.com"
          }
          # Only the deploy job of this environment: the sbs-admin workflow
          # runs it in the GitHub environment named like this AWS account's
          # environment (dev / prod), which puts ":environment:<name>" in the
          # token's sub. PR runs, other branches and the dev environment can
          # never assume the prod role. Add a required reviewer / branch rule
          # to the GitHub "prod" environment to gate prod deploys further.
          StringLike = {
            "token.actions.githubusercontent.com:sub" = "repo:${var.github_repo}@*:environment:${var.environment}"
          }
        }
      }
    ]
  })

  tags = {
    Environment = var.environment
  }
}

resource "aws_iam_role_policy" "s3_deploy" {
  name = "platform-admin-front-end-asset-deploy"
  role = aws_iam_role.this.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid      = "ListOwnBucket"
        Effect   = "Allow"
        Action   = "s3:ListBucket"
        Resource = "${var.platform_admin_bucket_arn}"
      },
      {
        Sid    = "SyncBuildOutputToOwnBucket"
        Effect = "Allow"
        Action = [
          "s3:PutObject",
          "s3:DeleteObject",
        ]
        Resource = "${var.platform_admin_bucket_arn}/*"
      }
    ]
  })
}

resource "aws_iam_role_policy" "cloudfront_invalidation" {
  name = "platform-admin-distribution-invalidation"
  role = aws_iam_role.this.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid      = "InvalidateOwnDistributionOnly"
        Effect   = "Allow"
        Action   = "cloudfront:CreateInvalidation"
        Resource = "${var.cloudfront_distribution_arn}"
      }
    ]
  })
}

resource "aws_iam_role_policy" "api_deploy" {
  name = "platform-tenants-image-deploy"
  role = aws_iam_role.this.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid      = "GetECRLoginToken"
        Effect   = "Allow"
        Action   = "ecr:GetAuthorizationToken"
        Resource = "*"
      },
      {
        Sid    = "PushToOwnRepoOnly"
        Effect = "Allow"
        Action = [
          "ecr:BatchCheckLayerAvailability",
          "ecr:BatchGetImage",
          "ecr:InitiateLayerUpload",
          "ecr:UploadLayerPart",
          "ecr:CompleteLayerUpload",
          "ecr:PutImage",
        ]
        Resource = "${var.api_ecr_repository_arn}"
      },
      {
        Sid    = "UpdateOwnFunctionOnly"
        Effect = "Allow"
        Action = [
          "lambda:UpdateFunctionCode",
          "lambda:GetFunction",
          "lambda:GetFunctionConfiguration",
        ]
        Resource = "${var.api_function_arn}"
      }
    ]
  })
}
