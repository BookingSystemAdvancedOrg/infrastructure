# Role assumed by the booqy-website repo's GitHub Actions pipeline via OIDC -
# no long-lived AWS credentials. Scoped to exactly what that pipeline needs:
# sync the public page to its own bucket, then invalidate its own CloudFront
# distribution. No access to any app bucket, distribution, ECR or Lambda.
#
# Prod only trusts runs in the repo's "prod" GitHub environment (deploys from
# main, with the environment's protection rules); dev trusts any run of the
# repo, like the other deploy roles.

locals {
  role_name = var.environment == "prod" ? "website-deploy-role" : "${var.environment}-website-deploy-role"
  allowed_sub = var.environment == "prod" ? (
    "repo:${var.github_repo}@*:environment:prod"
  ) : "repo:${var.github_repo}@*:*"
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
          StringLike = {
            "token.actions.githubusercontent.com:sub" = local.allowed_sub
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
  name = "website-deploy"
  role = aws_iam_role.this.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid      = "ListOwnBucket"
        Effect   = "Allow"
        Action   = "s3:ListBucket"
        Resource = var.website_bucket_arn
      },
      {
        Sid    = "SyncSiteToOwnBucket"
        Effect = "Allow"
        Action = [
          "s3:PutObject",
          "s3:DeleteObject",
        ]
        Resource = "${var.website_bucket_arn}/*"
      }
    ]
  })
}

resource "aws_iam_role_policy" "cloudfront_invalidation" {
  name = "website-distribution-invalidation"
  role = aws_iam_role.this.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid      = "InvalidateOwnDistributionOnly"
        Effect   = "Allow"
        Action   = "cloudfront:CreateInvalidation"
        Resource = var.cloudfront_distribution_arn
      }
    ]
  })
}
