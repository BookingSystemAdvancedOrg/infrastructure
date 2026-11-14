# Role assumed by the desktop installer workflow in admin-front-end and
# booqy-console (.github/workflows/desktop-installers.yml) via OIDC. It may
# only upload to the installer bucket (network/platform-domain/downloads.tf):
# no delete, no read of other buckets, no CloudFront, ECR or Lambda. Separate
# from the repos' deploy roles, which stay untouched.
#
# Prod only trusts runs in each repo's "prod" GitHub environment (builds from
# main); dev trusts any run of the two repos, like the other deploy roles.

locals {
  role_name = var.environment == "prod" ? "desktop-release-role" : "${var.environment}-desktop-release-role"
  allowed_subs = [
    for repo in var.github_repos : (
      var.environment == "prod" ? "repo:${repo}@*:environment:prod" : "repo:${repo}@*:*"
    )
  ]
}

resource "aws_iam_role" "this" {
  name = local.role_name

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect    = "Allow"
        Principal = { Federated = var.oidc_provider_arn }
        Action    = "sts:AssumeRoleWithWebIdentity"
        Condition = {
          StringEquals = {
            "token.actions.githubusercontent.com:aud" = "sts.amazonaws.com"
          }
          StringLike = {
            "token.actions.githubusercontent.com:sub" = local.allowed_subs
          }
        }
      }
    ]
  })

  tags = {
    Environment = var.environment
  }
}

resource "aws_iam_role_policy" "upload" {
  name = "desktop-installer-upload"
  role = aws_iam_role.this.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid      = "UploadInstallersOnly"
        Effect   = "Allow"
        Action   = "s3:PutObject"
        Resource = "${var.downloads_bucket_arn}/downloads/*"
      }
    ]
  })
}
