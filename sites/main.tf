# Restaurant websites, one per customer: every restaurant has its own private
# repo site-<slug> in the GitHub organisation (created from site-template by
# the site-repo function at onboarding) that deploys to its own folder
# sites/<tenantId>/ in the bucket below, through its own deploy role.
# application/docs/orchestrator/CUSTOMER-SITES-PLAN.md, docs/CUSTOMER-SITE-RUNBOOK.md.
#
#   sites bucket         private, read only by the multi-tenant distribution
#                        (origin path /sites/{{tenantId}}, platform-domain)
#   deploy boundary      fixed permissions boundary of every per-site deploy
#                        role: S3 writes to sites/<the role's tenantId tag>/
#                        only, nothing else
#   site-repo function   GitHub App "Booqy Sites" + IAM: creates the repo, the
#                        deploy role (/booqy-sites/, with the boundary), the
#                        repo variables and booqy.json; status, invite,
#                        redeploy and archive for Booqy Console
#
# The per-site deploy roles are created at runtime (one per customer per
# account), never here, and never touch the platform's own OIDC roles.

data "aws_caller_identity" "current" {}

locals {
  prefix    = var.environment == "prod" ? "" : "${var.environment}-"
  account   = data.aws_caller_identity.current.account_id
  function  = "site-repo"
  name      = "${local.prefix}${local.function}"
  role_path = "/booqy-sites/"
  # "-??????" is the random suffix Secrets Manager adds to a secret's ARN.
  app_secret_arn = "arn:aws:secretsmanager:${var.region}:${local.account}:secret:${var.github_app_secret_name}-??????"
  enabled        = var.github_app_secret_name != ""
}

# --- sites bucket ----------------------------------------------------------------

resource "aws_s3_bucket" "sites" {
  bucket = "${local.prefix}restaurant-sites-${local.account}"

  tags = {
    Environment = var.environment
  }
}

resource "aws_s3_bucket_public_access_block" "sites" {
  bucket = aws_s3_bucket.sites.id

  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

resource "aws_s3_bucket_ownership_controls" "sites" {
  bucket = aws_s3_bucket.sites.id

  rule {
    object_ownership = "BucketOwnerEnforced"
  }
}

resource "aws_s3_bucket_server_side_encryption_configuration" "sites" {
  bucket = aws_s3_bucket.sites.id

  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm = "AES256"
    }
  }
}

# A deploy replaces the folder (s3 sync --delete); the previous build stays
# as noncurrent versions for 30 days. Rollback = redeploy an older commit.
resource "aws_s3_bucket_versioning" "sites" {
  bucket = aws_s3_bucket.sites.id

  versioning_configuration {
    status = "Enabled"
  }
}

resource "aws_s3_bucket_lifecycle_configuration" "sites" {
  bucket = aws_s3_bucket.sites.id

  rule {
    id     = "expire-previous-builds"
    status = "Enabled"

    filter {}

    noncurrent_version_expiration {
      noncurrent_days = 30
    }

    expiration {
      expired_object_delete_marker = true
    }

    abort_incomplete_multipart_upload {
      days_after_initiation = 7
    }
  }

  depends_on = [aws_s3_bucket_versioning.sites]
}

resource "aws_s3_bucket_policy" "sites" {
  bucket = aws_s3_bucket.sites.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = concat(var.distribution_arn == "" ? [] : [
      {
        Sid       = "AllowTenantSitesDistributionReadOnly"
        Effect    = "Allow"
        Principal = { Service = "cloudfront.amazonaws.com" }
        Action    = "s3:GetObject"
        Resource  = "${aws_s3_bucket.sites.arn}/sites/*"
        Condition = {
          StringEquals = { "AWS:SourceArn" = var.distribution_arn }
        }
      }
      ], [
      {
        Sid       = "DenyInsecureTransport"
        Effect    = "Deny"
        Principal = "*"
        Action    = "s3:*"
        Resource  = [aws_s3_bucket.sites.arn, "${aws_s3_bucket.sites.arn}/*"]
        Condition = {
          Bool = { "aws:SecureTransport" = "false" }
        }
      }
    ])
  })

  depends_on = [aws_s3_bucket_public_access_block.sites]
}

# --- deploy boundary -----------------------------------------------------------------
#
# The ceiling of every per-site deploy role, whatever its own policy says:
# list, read, write and delete under sites/<tenantId>/ of this bucket, where
# tenantId is the role's own tag (set by site-repo when it creates the role;
# the deploy role itself has no IAM access and its trust allows no session
# tags, so the tag can't be changed from GitHub). Nothing else: no other
# folder, bucket, service or IAM action.
resource "aws_iam_policy" "deploy_boundary" {
  name        = "${local.prefix}booqy-sites-deploy-boundary"
  path        = local.role_path
  description = "Permissions boundary of the per-restaurant site deploy roles: S3 sites/<tenantId tag>/ only"

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid      = "OwnSiteFolder"
        Effect   = "Allow"
        Action   = ["s3:PutObject", "s3:GetObject", "s3:DeleteObject"]
        Resource = "${aws_s3_bucket.sites.arn}/sites/$${aws:PrincipalTag/tenantId}/*"
      },
      {
        Sid      = "ListOwnSiteFolder"
        Effect   = "Allow"
        Action   = "s3:ListBucket"
        Resource = aws_s3_bucket.sites.arn
        Condition = {
          StringLike = { "s3:prefix" = "sites/$${aws:PrincipalTag/tenantId}/*" }
        }
      },
    ]
  })

  tags = {
    Environment = var.environment
  }
}

# --- site-repo function -------------------------------------------------------------

resource "aws_iam_role" "fn" {
  name = "${local.name}-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect    = "Allow"
      Principal = { Service = "lambda.amazonaws.com" }
      Action    = "sts:AssumeRole"
    }]
  })

  tags = {
    Environment = var.environment
  }
}

resource "aws_iam_role_policy" "fn" {
  name = "${local.function}-access"
  role = aws_iam_role.fn.id
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = concat([
      {
        # The tenant's PROFILE (slug, name, primaryDomain, status) and its
        # SITE row (repo, role, status, lastError).
        Sid      = "TenantProfileAndSiteRow"
        Effect   = "Allow"
        Action   = ["dynamodb:GetItem", "dynamodb:PutItem", "dynamodb:UpdateItem"]
        Resource = var.tenant_table_arn
      },
      {
        # Per-site deploy roles: only under /booqy-sites/, and only created
        # or given a policy with the fixed boundary attached.
        Sid      = "CreateBoundedSiteRoles"
        Effect   = "Allow"
        Action   = ["iam:CreateRole", "iam:PutRolePolicy"]
        Resource = "arn:aws:iam::${local.account}:role${local.role_path}*"
        Condition = {
          StringEquals = { "iam:PermissionsBoundary" = aws_iam_policy.deploy_boundary.arn }
        }
      },
      {
        Sid    = "ManageSiteRoles"
        Effect = "Allow"
        Action = [
          "iam:GetRole", "iam:TagRole", "iam:UpdateAssumeRolePolicy", "iam:ListRolePolicies",
          "iam:DeleteRolePolicy", "iam:DeleteRole", "iam:SimulatePrincipalPolicy",
        ]
        Resource = "arn:aws:iam::${local.account}:role${local.role_path}*"
      },
      {
        # Belt and braces: the boundary of a site role can never be removed
        # or swapped, whatever is granted above.
        Sid      = "KeepBoundary"
        Effect   = "Deny"
        Action   = ["iam:DeleteRolePermissionsBoundary", "iam:PutRolePermissionsBoundary", "iam:AttachRolePolicy"]
        Resource = "arn:aws:iam::${local.account}:role${local.role_path}*"
      },
      ], local.enabled ? [
      {
        # The GitHub App's private key (JSON {app_id, private_key}), created
        # by hand (never by Terraform, so no key is in state).
        Sid      = "ReadGitHubAppKey"
        Effect   = "Allow"
        Action   = "secretsmanager:GetSecretValue"
        Resource = local.app_secret_arn
      },
    ] : [])
  })
}

resource "aws_iam_role_policy" "logs" {
  name = "cloudwatch-logs"
  role = aws_iam_role.fn.id
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Sid      = "WriteLogs"
      Effect   = "Allow"
      Action   = ["logs:CreateLogStream", "logs:PutLogEvents"]
      Resource = "arn:aws:logs:${var.region}:${local.account}:log-group:/aws/lambda/${local.name}:*"
    }]
  })
}

resource "aws_cloudwatch_log_group" "fn" {
  name              = "/aws/lambda/${local.name}"
  retention_in_days = 30

  tags = {
    Environment = var.environment
  }
}

resource "aws_lambda_function" "fn" {
  function_name = local.name
  role          = aws_iam_role.fn.arn
  package_type  = "Image"
  image_uri     = "${var.ecr_repository_url}:latest"
  publish       = true
  architectures = ["arm64"]
  # A new repo: GitHub generates it from the template (seconds), then
  # variables, booqy.json and the deploy role. Console calls stay short.
  timeout     = 120
  memory_size = 256

  lifecycle {
    ignore_changes = [image_uri]
  }

  environment {
    variables = {
      ENVIRONMENT            = var.environment
      TENANT_TABLE_NAME      = var.tenant_table_name
      GITHUB_ORG             = var.github_org
      GITHUB_APP_SECRET_ID   = var.github_app_secret_name
      SITE_TEMPLATE_REPO     = var.template_repo
      SITES_BUCKET           = aws_s3_bucket.sites.bucket
      DEPLOY_ROLE_PATH       = local.role_path
      DEPLOY_ROLE_PREFIX     = "${local.prefix}site-"
      DEPLOY_BOUNDARY_ARN    = aws_iam_policy.deploy_boundary.arn
      OIDC_PROVIDER_ARN      = var.oidc_provider_arn
      API_BASE_URL           = var.api_base_url
      MENU_IMAGE_BASE_URL    = var.menu_image_base_url
      PREVIEW_DOMAIN         = var.preview_domain
      STRIPE_PUBLISHABLE_KEY = var.stripe_publishable_key
      TURNSTILE_SITE_KEY     = var.turnstile_site_key
    }
  }

  depends_on = [aws_cloudwatch_log_group.fn, aws_iam_role_policy.logs]

  tags = {
    Environment = var.environment
  }
}

resource "aws_lambda_alias" "live" {
  name             = "live"
  function_name    = aws_lambda_function.fn.function_name
  function_version = aws_lambda_function.fn.version

  lifecycle {
    ignore_changes = [function_version, routing_config]
  }
}

resource "aws_cloudwatch_metric_alarm" "errors" {
  alarm_name        = "${local.name}-errors"
  alarm_description = "site-repo crashed: a restaurant's website repo, deploy role or console action failed. The tenant's Website tab shows the error and has Retry."
  namespace         = "AWS/Lambda"
  metric_name       = "Errors"
  dimensions        = { FunctionName = aws_lambda_function.fn.function_name }

  statistic           = "Sum"
  period              = 300
  evaluation_periods  = 1
  comparison_operator = "GreaterThanThreshold"
  threshold           = 0
  treat_missing_data  = "notBreaching"

  alarm_actions = [var.alert_topic_arn]

  tags = {
    Environment = var.environment
  }
}
