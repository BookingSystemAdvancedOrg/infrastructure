# Test sites: the sandbox for customers created in the DEV console (owner
# 2026-11-15). Dev only (the root refuses it in prod). Every dev console
# customer has a public repo site-<slug> in GitHub org BooqyCustomersDev
# whose two branches both deploy here, in the dev account:
#
#   main -> https://<slug>.test.booqy.se      bucket main/sites/<tenantId>/
#   dev  -> https://<slug>.test-dev.booqy.se  bucket dev/sites/<tenantId>/
#
# Real customers' dev sites (<slug>.dev.booqy.se, platform-domain) never
# share anything with this: own zones, certificate, bucket, distribution and
# deploy boundary, so the two can't collide.
#
#   test. / test-dev. zones   delegated from the booqy.se zone in prod
#                             (prod.tfvars platform_subdomain_delegations),
#                             phase 1 (var.zones_enabled via the module's count)
#   wildcard certificate      *.test.<domain> + *.test-dev.<domain> (us-east-1),
#                             one for every test host
#   sandbox bucket            private; main/ and dev/ never overwrite each other;
#                             _platform/robots.txt (Disallow: /), _platform/404.html
#   distribution              ONE standard distribution (no multi-tenant
#                             distribution tenants: those cost money beyond 10
#                             per account), aliases *.test.<domain> and
#                             *.test-dev.<domain>; X-Robots-Tag noindex, nofollow
#   host router               CloudFront Function + key value store (label ->
#                             tenantId): <label>.test.<domain> serves
#                             main/sites/<tenantId>/, <label>.test-dev.<domain>
#                             dev/sites/<tenantId>/, SPA fallback, unknown -> 404
#   DNS                       *.test.<domain> and *.test-dev.<domain> alias A/AAAA
#   deploy boundary           ceiling of every test site role
#                             (/booqy-test-sites/test-site-<slug>-main|dev):
#                             <stage tag>/sites/<tenantId tag>/ only
#
# Per-customer pieces (host map entries, the roles, repo variables) are
# written at runtime by site-repo, never here; nothing per customer costs
# money. Phase 2 (everything but the zones) is var.enabled.

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
# One certificate for both stages and every test host, also a dev console
# "own domain", which is mapped onto these zones (example-se.test.<domain>).

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
          StringEquals = { "AWS:SourceArn" = aws_cloudfront_distribution.sites[0].arn }
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

# The 404 page of a missing file (the distribution's error responses); the
# host router answers an unknown host itself.
resource "aws_s3_object" "not_found" {
  count = local.count

  bucket        = aws_s3_bucket.sites[0].id
  key           = "_platform/404.html"
  content       = "<!doctype html><html lang=\"sv\"><meta charset=\"utf-8\"><meta name=\"robots\" content=\"noindex\"><title>Sidan finns inte</title><body style=\"font-family:system-ui;padding:2rem\"><h1>Sidan finns inte</h1><p>Sidan du letar efter finns inte p\u00e5 den h\u00e4r testsajten.</p></body></html>\n"
  content_type  = "text/html; charset=utf-8"
  cache_control = "public, max-age=300"

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

# Label -> tenantId for the host router below: a test customer's slug (put by
# site-repo at provision) and each mapped own domain's label (example-se,
# put and deleted through site-repo by the Domains tab); site-repo deletes
# them all on offboarding and purge. Only site-repo writes it
# (cloudfront-keyvaluestore Put/Delete/Describe on this ARN, sites/main.tf).
resource "aws_cloudfront_key_value_store" "hosts" {
  count = local.count

  name    = "${local.prefix}test-sites-hosts"
  comment = "Test sites: host label -> tenantId (written by site-repo)"
}

# Viewer request: Host -> <stage>/sites/<tenantId>/ (test.<domain> main,
# test-dev.<domain> dev), SPA fallback to index.html, /robots.txt from
# _platform/, unknown host -> 404. Unit test: function/host-router.test.mjs.
resource "aws_cloudfront_function" "host_router" {
  count = local.count

  name    = "${local.prefix}test-sites-host-router"
  runtime = "cloudfront-js-2.0"
  comment = "Test sites: host label -> stage folder of the tenant (key value store)"
  publish = true
  code = templatefile("${path.module}/function/host-router.js", {
    # The store's ID (cf.kvs() needs it), the last part of its ARN
    # (arn:aws:cloudfront::<account>:key-value-store/<id>); the resource's
    # own id attribute is its name.
    kvs_id      = element(split("/", aws_cloudfront_key_value_store.hosts[0].arn), 1)
    main_domain = var.main_domain
    dev_domain  = var.dev_domain
  })
  key_value_store_associations = [aws_cloudfront_key_value_store.hosts[0].arn]
}

# Viewer request on /api/*: strip /api, pass the viewer's IP and host for the
# API (trusted only with the x-booqy-edge origin header).
resource "aws_cloudfront_function" "api_proxy" {
  count = local.count

  name    = "${local.prefix}test-sites-api-proxy"
  runtime = "cloudfront-js-2.0"
  comment = "Test sites /api/*: strip prefix, pass viewer IP and host"
  publish = true
  code    = file("${path.module}/function/api-proxy.js")
}

# ONE standard distribution for every test host (owner 2026-11-15: no
# distribution tenants, which cost money beyond 10 per account, and no
# certificate per host): both wildcards on the one certificate.
resource "aws_cloudfront_distribution" "sites" {
  count = local.count

  enabled             = true
  comment             = "${local.prefix}test sites (sandbox): *.${var.main_domain} main, *.${var.dev_domain} dev"
  web_acl_id          = var.web_acl_arn != "" ? var.web_acl_arn : null
  aliases             = ["*.${var.main_domain}", "*.${var.dev_domain}"]
  is_ipv6_enabled     = true
  http_version        = "http2and3"
  price_class         = "PriceClass_100"
  wait_for_deployment = false

  # No origin path: the host router writes the whole key
  # (<stage>/sites/<tenantId>/..., _platform/robots.txt).
  origin {
    origin_id                = "sandbox"
    domain_name              = aws_s3_bucket.sites[0].bucket_regional_domain_name
    origin_access_control_id = aws_cloudfront_origin_access_control.sites[0].id
  }

  origin {
    origin_id                = "menu-image"
    domain_name              = var.menu_image_bucket_regional_domain_name
    origin_access_control_id = aws_cloudfront_origin_access_control.sites[0].id
  }

  # The API, for the sites' form posts under /api/* (as on the multi-tenant
  # distribution, network/platform-domain): same domain as the page, so the
  # web ACL's bot check token goes with every post.
  dynamic "origin" {
    for_each = var.api_origin_domain == "" ? [] : [1]
    content {
      origin_id   = "api"
      domain_name = var.api_origin_domain

      custom_origin_config {
        http_port              = 80
        https_port             = 443
        origin_protocol_policy = "https-only"
        origin_ssl_protocols   = ["TLSv1.2"]
      }

      custom_header {
        name  = "x-booqy-waf"
        value = var.waf_edge_secret
      }
    }
  }

  default_cache_behavior {
    target_origin_id           = "sandbox"
    viewer_protocol_policy     = "redirect-to-https"
    allowed_methods            = ["GET", "HEAD"]
    cached_methods             = ["GET", "HEAD"]
    cache_policy_id            = local.caching_optimized
    response_headers_policy_id = aws_cloudfront_response_headers_policy.sites[0].id
    compress                   = true

    function_association {
      event_type   = "viewer-request"
      function_arn = aws_cloudfront_function.host_router[0].arn
    }
  }

  # Same path as the other distributions, so a site works unchanged here.
  ordered_cache_behavior {
    path_pattern               = "/menu-images/*"
    target_origin_id           = "menu-image"
    viewer_protocol_policy     = "redirect-to-https"
    allowed_methods            = ["GET", "HEAD"]
    cached_methods             = ["GET", "HEAD"]
    cache_policy_id            = local.caching_optimized
    response_headers_policy_id = aws_cloudfront_response_headers_policy.sites[0].id
    compress                   = true
  }

  # Form posts from the site (shared/bot_check.py in the API): never cached,
  # every viewer header but Host, /api stripped.
  dynamic "ordered_cache_behavior" {
    for_each = var.api_origin_domain == "" ? [] : [1]
    content {
      path_pattern             = "/api/*"
      target_origin_id         = "api"
      viewer_protocol_policy   = "https-only"
      allowed_methods          = ["DELETE", "GET", "HEAD", "OPTIONS", "PATCH", "POST", "PUT"]
      cached_methods           = ["GET", "HEAD"]
      cache_policy_id          = "4135ea2d-6df8-44a3-9df3-4b5a84be39ad" # AWS managed "CachingDisabled"
      origin_request_policy_id = "b689b0a8-53d0-40ab-baf2-68738e2966ac" # AWS managed "AllViewerExceptHostHeader"
      compress                 = false

      function_association {
        event_type   = "viewer-request"
        function_arn = aws_cloudfront_function.api_proxy[0].arn
      }
    }
  }

  # No custom_error_response: it applies to the whole distribution and would
  # turn the API's own 403/404 answers under /api/* into HTML. The host
  # router already sends client-side routes to index.html and unknown hosts
  # to a 404 page; a missing file gets S3's own 403.

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

# Every test host (a slug or a mapped own domain) answers through the one
# distribution: no per-customer DNS.
resource "aws_route53_record" "wildcard" {
  for_each = var.enabled ? {
    "main-A"    = { zone = aws_route53_zone.main.zone_id, name = "*.${var.main_domain}", type = "A" }
    "main-AAAA" = { zone = aws_route53_zone.main.zone_id, name = "*.${var.main_domain}", type = "AAAA" }
    "dev-A"     = { zone = aws_route53_zone.dev.zone_id, name = "*.${var.dev_domain}", type = "A" }
    "dev-AAAA"  = { zone = aws_route53_zone.dev.zone_id, name = "*.${var.dev_domain}", type = "AAAA" }
  } : {}

  zone_id = each.value.zone
  name    = each.value.name
  type    = each.value.type

  alias {
    name                   = aws_cloudfront_distribution.sites[0].domain_name
    zone_id                = aws_cloudfront_distribution.sites[0].hosted_zone_id
    evaluate_target_health = false
  }
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
