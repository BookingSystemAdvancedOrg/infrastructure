# Role assumed by the admin front-end repo's GitHub Actions pipeline via
# OIDC - no long-lived AWS credentials stored as a repo secret. Scoped to
# exactly what that pipeline needs: sync the built site to its own S3
# bucket, then invalidate its own CloudFront distribution. No access to
# the customer bucket/distribution, ECR, or Lambda - a compromise of this
# repo's CI can't reach any of those.

locals {
  role_name = var.environment == "prod" ? "admin-front-end-deploy-role" : "${var.environment}-admin-front-end-deploy-role"
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
          # Repo-wide, any branch/event for now - tighten to a specific
          # ref (e.g. "repo:${var.github_repo}:ref:refs/heads/main") once
          # this repo's branch/deploy strategy is settled.
          StringLike = {
            "token.actions.githubusercontent.com:sub" = "repo:${var.github_repo}@*:*"
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
  name = "admin-front-end-asset-deploy"
  role = aws_iam_role.this.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid      = "ListOwnBucket"
        Effect   = "Allow"
        Action   = "s3:ListBucket"
        Resource = "${var.admin_bucket_arn}"
      },
      {
        Sid    = "SyncBuildOutputToOwnBucket"
        Effect = "Allow"
        Action = [
          "s3:PutObject",
          "s3:DeleteObject",
        ]
        Resource = "${var.admin_bucket_arn}/*"
      }
    ]
  })
}

resource "aws_iam_role_policy" "cloudfront_invalidation" {
  name = "private-distribution-invalidation"
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
