# Role the tenant WEBSITE repos' GitHub Actions pipelines assume via OIDC to
# publish a site: sync the build to s3://<tenant-sites>/<tenantId>/ and
# invalidate that tenant's distribution tenant(s). One role for every site
# repo in your organization whose name matches var.site_repo_pattern
# (e.g. site-*), so a new customer's site needs a new repo, not new IAM.
#
# Trade-off, deliberately accepted: IAM can't tie "repo site-x" to "prefix
# <tenantId of x>" (GitHub's OIDC token carries no per-tenant session tag),
# so any matching repo could write any tenant's prefix. All site repos are
# built by your own team inside your org - keep the pattern narrow and
# branch-protect those repos. The placeholder prefix is off-limits.

data "aws_caller_identity" "current" {}

locals {
  role_name = var.environment == "prod" ? "tenant-sites-deploy-role" : "${var.environment}-tenant-sites-deploy-role"
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
            "token.actions.githubusercontent.com:sub" = "repo:${var.github_org}@*/${var.site_repo_pattern}@*:*"
          }
        }
      }
    ]
  })

  tags = {
    Environment = var.environment
  }
}

resource "aws_iam_role_policy" "deploy" {
  name = "tenant-sites-deploy"
  role = aws_iam_role.this.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid      = "ListSitesBucket"
        Effect   = "Allow"
        Action   = "s3:ListBucket"
        Resource = "${var.sites_bucket_arn}"
      },
      {
        Sid    = "SyncTenantSiteFiles"
        Effect = "Allow"
        Action = [
          "s3:PutObject",
          "s3:DeleteObject",
        ]
        Resource = "${var.sites_bucket_arn}/*"
      },
      {
        Sid    = "NeverTouchThePlaceholder"
        Effect = "Deny"
        Action = [
          "s3:PutObject",
          "s3:DeleteObject",
        ]
        Resource = "${var.sites_bucket_arn}/_placeholder/*"
      },
      {
        Sid    = "InvalidateTenantSite"
        Effect = "Allow"
        Action = [
          "cloudfront:CreateInvalidationForDistributionTenant",
          "cloudfront:GetDistributionTenant",
        ]
        Resource = "arn:aws:cloudfront::${data.aws_caller_identity.current.account_id}:distribution-tenant/*"
      },
      {
        # Lets the pipeline find the tenant's distribution tenant(s) by its
        # tenantId parameter; List actions have no resource-level scope.
        Sid      = "FindTenantDistributions"
        Effect   = "Allow"
        Action   = "cloudfront:ListDistributionTenants"
        Resource = "*"
      }
    ]
  })
}
