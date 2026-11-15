# Test sites: the sandbox for customers created in the DEV console (owner
# 2026-11-15). Dev only (the root refuses it in prod). Every dev console
# customer has a public repo site-<slug> in GitHub org BooqyCustomersDev
# whose two branches both deploy here, in the dev account:
#
#   main -> https://<slug>.test.booqy.se      bucket main/sites/<tenantId>/
#   dev  -> https://<slug>.test-dev.booqy.se  bucket dev/sites/<tenantId>/
#
# Real customers' dev sites (<slug>.dev.booqy.se, platform-domain) never
# share anything with this: own zones, certificate, bucket, distribution,
# connection group and deploy boundary, so the two can't collide.
#
#   test. / test-dev. zones   delegated from the booqy.se zone in prod
#                             (prod.tfvars platform_subdomain_delegations),
#                             phase 1 (var.zones_enabled via the module's count)
#   wildcard certificate      *.test.<domain> + *.test-dev.<domain> (us-east-1)
#   sandbox bucket            private; main/ and dev/ never overwrite each other;
#                             _platform/robots.txt (Disallow: /)
#   multi-tenant distribution one distribution tenant per hostname, parameters
#                             tenantId and stage (main | dev) pick the folder;
#                             X-Robots-Tag noindex, nofollow on every answer
#   connection group          *.test.<domain> and *.test-dev.<domain> CNAME to it
#   deploy boundary           ceiling of every test site role
#                             (/booqy-test-sites/test-site-<slug>-main|dev):
#                             <stage tag>/sites/<tenantId tag>/ only
#
# Per-customer pieces (distribution tenants, the roles, repo variables) are
# created at runtime by the onboarding/domain workflows and site-repo, never
# here. Phase 2 (everything but the zones) is var.enabled.

terraform {
  required_providers {
    aws = {
      source                = "hashicorp/aws"
      configuration_aliases = [aws.us_east_1]
    }
  }
}

data "aws_caller_identity" "current" {}

locals {
  prefix  = "${var.environment}-"
  account = data.aws_caller_identity.current.account_id
  count   = var.enabled ? 1 : 0
  # AWS managed cache policy "CachingOptimized" (honours the object's
  # Cache-Control: index.html no-cache, hashed assets immutable).
  caching_optimized = "658327ea-f89d-4fab-a63d-7e88639e58f6"
  zone_ids = {
    (var.main_domain) = aws_route53_zone.main.zone_id
    (var.dev_domain)  = aws_route53_zone.dev.zone_id
  }
}

# --- Zones (phase 1) ---------------------------------------------------------------

resource "aws_route53_zone" "main" {
  name    = var.main_domain
  comment = "Test sites, main branch (${var.environment}) - delegated from the parent zone in prod"

  tags = {
    Environment = var.environment
  }
}

resource "aws_route53_zone" "dev" {
  name    = var.dev_domain
  comment = "Test sites, dev branch (${var.environment}) - delegated from the parent zone in prod"

  tags = {
    Environment = var.environment
  }
}

# --- Certificate ---------------------------------------------------------------------
#
# One certificate for both stages: the distribution's default certificate,
# inherited by every distribution tenant (no per-tenant certificate, also
# for a dev console "own domain", which is mapped onto these zones).

resource "aws_acm_certificate" "wildcard" {
  count    = local.count
  provider = aws.us_east_1

  domain_name               = "*.${var.main_domain}"
  subject_alternative_names = ["*.${var.dev_domain}"]
  validation_method         = "DNS"

  lifecycle {
    create_before_destroy = true
  }

  tags = {
    Environment = var.environment
  }
}

# Each validation record goes into its own zone (keyed by the domain, known
# at plan time).
resource "aws_route53_record" "certificate_validation" {
  for_each = var.enabled ? {
    for o in aws_acm_certificate.wildcard[0].domain_validation_options : o.domain_name => {
      name   = o.resource_record_name
      record = o.resource_record_value
      type   = o.resource_record_type
    }
  } : {}

  zone_id         = local.zone_ids[trimprefix(each.key, "*.")]
  name            = each.value.name
  type            = each.value.type
  records         = [each.value.record]
  ttl             = 300
  allow_overwrite = true
}

resource "aws_acm_certificate_validation" "wildcard" {
  count    = local.count
  provider = aws.us_east_1

  certificate_arn         = aws_acm_certificate.wildcard[0].arn
  validation_record_fqdns = [for r in aws_route53_record.certificate_validation : r.fqdn]
}

# --- Sandbox bucket --------------------------------------------------------------------

resource "aws_s3_bucket" "sites" {
  count  = local.count
  bucket = "${local.prefix}restaurant-sites-test-${local.account}"

  tags = {
    Environment = var.environment
  }
}

resource "aws_s3_bucket_public_access_block" "sites" {
  count  = local.count
  bucket = aws_s3_bucket.sites[0].id

  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

resource "aws_s3_bucket_ownership_controls" "sites" {
  count  = local.count
  bucket = aws_s3_bucket.sites[0].id

  rule {
    object_ownership = "BucketOwnerEnforced"
  }
}

resource "aws_s3_bucket_server_side_encryption_configuration" "sites" {
  count  = local.count
  bucket = aws_s3_bucket.sites[0].id

  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm = "AES256"
    }
  }
}

resource "aws_s3_bucket_versioning" "sites" {
  count  = local.count
  bucket = aws_s3_bucket.sites[0].id

  versioning_configuration {
    status = "Enabled"
  }
}

# Test builds: the previous build is kept a week only.
resource "aws_s3_bucket_lifecycle_configuration" "sites" {
  count  = local.count
  bucket = aws_s3_bucket.sites[0].id

  rule {
    id     = "expire-previous-builds"
    status = "Enabled"

    filter {}

    noncurrent_version_expiration {
      noncurrent_days = 7
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
  count  = local.count
  bucket = aws_s3_bucket.sites[0].id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid       = "AllowTestSitesDistributionReadOnly"
        Effect    = "Allow"
        Principal = { Service = "cloudfront.amazonaws.com" }
        Action    = "s3:GetObject"
        Resource = [
          "${aws_s3_bucket.sites[0].arn}/main/sites/*",
          "${aws_s3_bucket.sites[0].arn}/dev/sites/*",
          "${aws_s3_bucket.sites[0].arn}/_platform/*",
        ]
        Condition = {
          StringEquals = { "AWS:SourceArn" = aws_cloudfront_multitenant_distribution.sites[0].arn }
        }
      },
      {
        Sid       = "DenyInsecureTransport"
        Effect    = "Deny"
        Principal = "*"
        Action    = "s3:*"
        Resource  = [aws_s3_bucket.sites[0].arn, "${aws_s3_bucket.sites[0].arn}/*"]
        Condition = {
          Bool = { "aws:SecureTransport" = "false" }
        }
      },
    ]
  })

  depends_on = [aws_s3_bucket_public_access_block.sites]
}

# Served for /robots.txt on every test host, whatever the site's build has.
resource "aws_s3_object" "robots" {
  count = local.count

  bucket        = aws_s3_bucket.sites[0].id
  key           = "_platform/robots.txt"
  content       = "User-agent: *\nDisallow: /\n"
  content_type  = "text/plain; charset=utf-8"
  cache_control = "public, max-age=3600"

  depends_on = [aws_s3_bucket_ownership_controls.sites]
}

# --- CloudFront ------------------------------------------------------------------------

# One OAC signs for every S3 origin (sandbox bucket and menu images); each
# bucket's policy admits this distribution.
resource "aws_cloudfront_origin_access_control" "sites" {
  count = local.count

  name                              = "${local.prefix}test-sites-oac"
  origin_access_control_origin_type = "s3"
  signing_behavior                  = "always"
  signing_protocol                  = "sigv4"
}

# The real sites' security headers plus noindex on every answer: a test
# site is never a search result.
resource "aws_cloudfront_response_headers_policy" "sites" {
  count = local.count

  name    = "${local.prefix}test-site-headers"
  comment = "Test sites: HSTS, no framing, nosniff, fonts for Stripe, noindex"

  cors_config {
    access_control_allow_credentials = false
    origin_override                  = true
    access_control_max_age_sec       = 86400

    access_control_allow_headers {
      items = ["*"]
    }
    access_control_allow_methods {
      items = ["GET", "HEAD"]
    }
    access_control_allow_origins {
      items = ["https://js.stripe.com"]
    }
  }

  security_headers_config {
    content_security_policy {
      content_security_policy = "frame-ancestors 'none'"
      override                = true
    }
    content_type_options {
      override = true
    }
    frame_options {
      frame_option = "DENY"
      override     = true
    }
    referrer_policy {
      referrer_policy = "strict-origin-when-cross-origin"
      override        = false
    }
    strict_transport_security {
      access_control_max_age_sec = 63072000
      include_subdomains         = false
      preload                    = false
      override                   = true
    }
  }

  custom_headers_config {
    items {
      header   = "X-Robots-Tag"
      value    = "noindex, nofollow"
      override = true
    }
  }
}

resource "aws_cloudfront_multitenant_distribution" "sites" {
  count = local.count

  enabled             = true
  comment             = "${local.prefix}test sites (sandbox, one distribution tenant per test host)"
  default_root_object = "index.html"
  http_version        = "http2and3"

  # Set by the onboarding and domain-attach workflows on every distribution
  # tenant: whose site and which branch's build.
  tenant_config {
    parameter_definition {
      name = "tenantId"
      definition {
        string_schema {
          required = true
          comment  = "Test customer whose host this distribution tenant serves"
        }
      }
    }
    parameter_definition {
      name = "stage"
      definition {
        string_schema {
          required = true
          comment  = "main (test.<domain>) or dev (test-dev.<domain>): the build folder"
        }
      }
    }
  }

  # Both parameters in the origin path: <stage>/sites/<tenantId>/ is the
  # folder only that stage's deploy role of that customer may write.
  origin {
    id                       = "test-site"
    domain_name              = aws_s3_bucket.sites[0].bucket_regional_domain_name
    origin_path              = "/{{stage}}/sites/{{tenantId}}"
    origin_access_control_id = aws_cloudfront_origin_access_control.sites[0].id
  }

  origin {
    id                       = "platform-static"
    domain_name              = aws_s3_bucket.sites[0].bucket_regional_domain_name
    origin_path              = "/_platform"
    origin_access_control_id = aws_cloudfront_origin_access_control.sites[0].id
  }

  origin {
    id                       = "menu-image"
    domain_name              = var.menu_image_bucket_regional_domain_name
    origin_access_control_id = aws_cloudfront_origin_access_control.sites[0].id
  }

  default_cache_behavior {
    target_origin_id           = "test-site"
    viewer_protocol_policy     = "redirect-to-https"
    cache_policy_id            = local.caching_optimized
    response_headers_policy_id = aws_cloudfront_response_headers_policy.sites[0].id
    compress                   = true

    allowed_methods {
      items          = ["GET", "HEAD"]
      cached_methods = ["GET", "HEAD"]
    }
  }

  cache_behavior {
    path_pattern               = "/robots.txt"
    target_origin_id           = "platform-static"
    viewer_protocol_policy     = "redirect-to-https"
    cache_policy_id            = local.caching_optimized
    response_headers_policy_id = aws_cloudfront_response_headers_policy.sites[0].id
    compress                   = true

    allowed_methods {
      items          = ["GET", "HEAD"]
      cached_methods = ["GET", "HEAD"]
    }
  }

  # Same path as the other distributions, so a site works unchanged here.
  cache_behavior {
    path_pattern               = "/menu-images/*"
    target_origin_id           = "menu-image"
    viewer_protocol_policy     = "redirect-to-https"
    cache_policy_id            = local.caching_optimized
    response_headers_policy_id = aws_cloudfront_response_headers_policy.sites[0].id
    compress                   = true

    allowed_methods {
      items          = ["GET", "HEAD"]
      cached_methods = ["GET", "HEAD"]
    }
  }

  # SPAs with client-side routing: unknown paths load index.html.
  custom_error_response {
    error_code         = 403
    response_code      = "200"
    response_page_path = "/index.html"
  }

  custom_error_response {
    error_code         = 404
    response_code      = "200"
    response_page_path = "/index.html"
  }

  restrictions {
    geo_restriction {
      restriction_type = "none"
    }
  }

  viewer_certificate {
    acm_certificate_arn      = aws_acm_certificate_validation.wildcard[0].certificate_arn
    ssl_support_method       = "sni-only"
    minimum_protocol_version = "TLSv1.2_2021"
  }

  tags = {
    Environment = var.environment
  }
}

resource "aws_cloudfront_connection_group" "sites" {
  count = local.count

  name         = "${local.prefix}test-sites"
  enabled      = true
  ipv6_enabled = true

  tags = {
    Environment = var.environment
  }
}

# Every test host (a slug or a mapped own domain) answers through the
# connection group: no per-customer DNS.
resource "aws_route53_record" "main_wildcard" {
  count = local.count

  zone_id = aws_route53_zone.main.zone_id
  name    = "*.${var.main_domain}"
  type    = "CNAME"
  ttl     = 300
  records = [aws_cloudfront_connection_group.sites[0].routing_endpoint]
}

resource "aws_route53_record" "dev_wildcard" {
  count = local.count

  zone_id = aws_route53_zone.dev.zone_id
  name    = "*.${var.dev_domain}"
  type    = "CNAME"
  ttl     = 300
  records = [aws_cloudfront_connection_group.sites[0].routing_endpoint]
}

# --- Deploy boundary --------------------------------------------------------------------
#
# The ceiling of every test site deploy role, whatever its own policy says:
# list, read, write and delete under <stage>/sites/<tenantId>/ of the
# sandbox bucket, where stage and tenantId are the role's own tags (set by
# site-repo; the role has no IAM access and its trust allows no session
# tags). Not the other stage's folder, not _platform/, nothing else.
resource "aws_iam_policy" "deploy_boundary" {
  count = local.count

  name        = "${local.prefix}booqy-test-sites-deploy-boundary"
  path        = "/booqy-test-sites/"
  description = "Permissions boundary of the test site deploy roles: S3 <stage tag>/sites/<tenantId tag>/ of the sandbox only"

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid      = "OwnStageFolder"
        Effect   = "Allow"
        Action   = ["s3:PutObject", "s3:GetObject", "s3:DeleteObject"]
        Resource = "${aws_s3_bucket.sites[0].arn}/$${aws:PrincipalTag/stage}/sites/$${aws:PrincipalTag/tenantId}/*"
      },
      {
        Sid      = "ListOwnStageFolder"
        Effect   = "Allow"
        Action   = "s3:ListBucket"
        Resource = aws_s3_bucket.sites[0].arn
        Condition = {
          StringLike = { "s3:prefix" = "$${aws:PrincipalTag/stage}/sites/$${aws:PrincipalTag/tenantId}/*" }
        }
      },
    ]
  })

  tags = {
    Environment = var.environment
  }
}
