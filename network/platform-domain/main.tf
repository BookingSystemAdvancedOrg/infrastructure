# Everything that needs a domain the platform owns. Created only when root
# var.platform_domain is set (count on the module call), so the rest of the
# stack deploys and works on *.cloudfront.net / execute-api URLs until the
# domain is decided.
#
#   <domain> hosted zone          delegate the domain to its name servers
#   *.<domain> + <domain> cert    ACM (us-east-1), DNS-validated in that zone
#   tenant-sites bucket           every tenant website under <tenantId>/
#   multi-tenant distribution     CloudFront SaaS Manager template: the
#                                 tenantId parameter picks the S3 prefix
#   connection group              the CNAME target customers point at
#   *.<domain>  -> connection group   <slug>.<domain> needs no per-tenant DNS
#   app.<domain> / ops.<domain>   restaurant admin app / operator app
#   mail.<domain>                 SES sending domain (DKIM, MAIL FROM, DMARC)
#
# Per-tenant pieces (distribution tenants, customer domains, their managed
# certificates) are created at runtime by orchestration/tenant-workflows -
# never here.

terraform {
  required_providers {
    aws = {
      source                = "hashicorp/aws"
      configuration_aliases = [aws.us_east_1]
    }
  }
}

data "aws_caller_identity" "current" {}
data "aws_region" "current" {}

locals {
  prefix      = var.environment == "prod" ? "" : "${var.environment}-"
  mail_domain = "mail.${var.platform_domain}"
  # CloudFront's fixed hosted zone ID for alias records
  cloudfront_zone_id = "Z2FDTNDATAQYW2"
}

# --- DNS -----------------------------------------------------------------------

resource "aws_route53_zone" "platform" {
  name    = var.platform_domain
  comment = "Platform domain (${var.environment}) - delegate to the name servers in output platform_domain_name_servers"

  tags = {
    Environment = var.environment
  }
}

# --- Certificate ---------------------------------------------------------------
#
# One wildcard certificate covers app., ops. and every <slug>. subdomain.
# Customer domains never use it - each gets its own CloudFront-managed
# certificate when attached (domain-attach workflow).

resource "aws_acm_certificate" "wildcard" {
  provider = aws.us_east_1

  domain_name               = "*.${var.platform_domain}"
  subject_alternative_names = [var.platform_domain]
  validation_method         = "DNS"

  lifecycle {
    create_before_destroy = true
  }

  tags = {
    Environment = var.environment
  }
}

# Keyed by domain_name (known at plan time). *.<domain> and <domain> get the
# SAME validation record from ACM, so the two entries write one record -
# allow_overwrite makes that idempotent.
resource "aws_route53_record" "certificate_validation" {
  for_each = {
    for o in aws_acm_certificate.wildcard.domain_validation_options : o.domain_name => {
      name   = o.resource_record_name
      record = o.resource_record_value
      type   = o.resource_record_type
    }
  }

  zone_id         = aws_route53_zone.platform.zone_id
  name            = each.value.name
  type            = each.value.type
  records         = [each.value.record]
  ttl             = 300
  allow_overwrite = true
}

resource "aws_acm_certificate_validation" "wildcard" {
  provider = aws.us_east_1

  certificate_arn         = aws_acm_certificate.wildcard.arn
  validation_record_fqdns = [for r in aws_route53_record.certificate_validation : r.fqdn]
}

# --- Tenant websites bucket ----------------------------------------------------
#
# <tenantId>/... per tenant. Only the multi-tenant distribution can read it
# (OAC); the site deploy role (security/iam/oidc/tenant-sites-deploy-role)
# writes to it. Versioned so a bad deploy of one tenant's site can be rolled
# back object by object.

resource "aws_s3_bucket" "sites" {
  bucket = "${local.prefix}tenant-sites-${data.aws_caller_identity.current.account_id}"

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

resource "aws_s3_bucket_versioning" "sites" {
  bucket = aws_s3_bucket.sites.id

  versioning_configuration {
    status = "Enabled"
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

resource "aws_s3_bucket_lifecycle_configuration" "sites" {
  bucket = aws_s3_bucket.sites.id

  rule {
    id     = "expire-replaced-site-files"
    status = "Enabled"

    filter {}

    noncurrent_version_expiration {
      noncurrent_days = 30
    }
  }
}

resource "aws_s3_bucket_policy" "sites" {
  bucket = aws_s3_bucket.sites.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid       = "AllowTenantDistributionReadOnly"
        Effect    = "Allow"
        Principal = { Service = "cloudfront.amazonaws.com" }
        Action    = "s3:GetObject"
        Resource  = "${aws_s3_bucket.sites.arn}/*"
        Condition = {
          StringEquals = {
            "AWS:SourceArn" = aws_cloudfront_multitenant_distribution.tenants.arn
          }
        }
      },
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
    ]
  })

  depends_on = [aws_s3_bucket_public_access_block.sites]
}

# The page onboarding copies to <tenantId>/index.html so a new tenant's
# subdomain shows "coming soon" instead of an error until its real site is
# deployed. Never copied over an existing site.
resource "aws_s3_object" "placeholder" {
  bucket        = aws_s3_bucket.sites.id
  key           = var.site_placeholder_key
  content       = file("${path.module}/files/coming-soon.html")
  content_type  = "text/html; charset=utf-8"
  cache_control = "no-cache"
  etag          = filemd5("${path.module}/files/coming-soon.html")
}

# --- CloudFront: multi-tenant distribution ------------------------------------

resource "aws_cloudfront_origin_access_control" "sites" {
  name                              = "${local.prefix}tenant-sites-oac"
  origin_access_control_origin_type = "s3"
  signing_behavior                  = "always"
  signing_protocol                  = "sigv4"
}

resource "aws_cloudfront_origin_access_control" "menu_image" {
  name                              = "${local.prefix}tenant-sites-menu-image-oac"
  origin_access_control_origin_type = "s3"
  signing_behavior                  = "always"
  signing_protocol                  = "sigv4"
}

resource "aws_cloudfront_multitenant_distribution" "tenants" {
  enabled             = true
  comment             = "${local.prefix}tenant websites (one distribution tenant per site/domain)"
  default_root_object = "index.html"
  http_version        = "http2and3"
  web_acl_id          = var.web_acl_arn != "" ? var.web_acl_arn : null

  # Each distribution tenant passes its tenantId; it becomes the S3 prefix.
  tenant_config {
    parameter_definition {
      name = "tenantId"
      definition {
        string_schema {
          required = true
          comment  = "Tenant whose site this distribution tenant serves (S3 prefix in the tenant-sites bucket)"
        }
      }
    }
  }

  origin {
    id                       = "tenant-sites"
    domain_name              = aws_s3_bucket.sites.bucket_regional_domain_name
    origin_path              = "/{{tenantId}}"
    origin_access_control_id = aws_cloudfront_origin_access_control.sites.id
  }

  origin {
    id                       = "menu-image"
    domain_name              = var.menu_image_bucket_regional_domain_name
    origin_access_control_id = aws_cloudfront_origin_access_control.menu_image.id
  }

  default_cache_behavior {
    target_origin_id       = "tenant-sites"
    viewer_protocol_policy = "redirect-to-https"
    cache_policy_id        = "658327ea-f89d-4fab-a63d-7e88639e58f6" # AWS managed "CachingOptimized"
    compress               = true

    allowed_methods {
      items          = ["GET", "HEAD"]
      cached_methods = ["GET", "HEAD"]
    }
  }

  # Same path the other two distributions serve menu images at, so a site
  # built against the public distribution works unchanged on a tenant domain.
  cache_behavior {
    path_pattern           = "/menu-images/*"
    target_origin_id       = "menu-image"
    viewer_protocol_policy = "redirect-to-https"
    cache_policy_id        = "658327ea-f89d-4fab-a63d-7e88639e58f6" # AWS managed "CachingOptimized"
    compress               = true

    allowed_methods {
      items          = ["GET", "HEAD"]
      cached_methods = ["GET", "HEAD"]
    }
  }

  # Tenant sites are SPAs with client-side routing (same reasoning as the
  # admin distribution): unknown paths load index.html and the app routes.
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

  # Inherited by every <slug>.<domain> distribution tenant. Customer domains
  # replace it with their own managed certificate.
  viewer_certificate {
    acm_certificate_arn      = aws_acm_certificate_validation.wildcard.certificate_arn
    ssl_support_method       = "sni-only"
    minimum_protocol_version = "TLSv1.2_2021"
  }

  tags = {
    Environment = var.environment
  }
}

# The routing endpoint every distribution tenant is reached through: the
# wildcard record below for <slug>.<domain>, and the CNAME target customers
# set for their own domain.
resource "aws_cloudfront_connection_group" "tenants" {
  name         = "${local.prefix}tenant-sites"
  enabled      = true
  ipv6_enabled = true

  tags = {
    Environment = var.environment
  }
}

resource "aws_route53_record" "tenant_wildcard" {
  zone_id = aws_route53_zone.platform.zone_id
  name    = "*.${var.platform_domain}"
  type    = "CNAME"
  ttl     = 300
  records = [aws_cloudfront_connection_group.tenants.routing_endpoint]
}

# --- Fixed hostnames for the two admin apps ---------------------------------------
# More specific than the wildcard, so they win over it.

resource "aws_route53_record" "app" {
  for_each = toset(["A", "AAAA"])

  zone_id = aws_route53_zone.platform.zone_id
  name    = "app.${var.platform_domain}"
  type    = each.value

  alias {
    name                   = var.admin_distribution_domain_name
    zone_id                = local.cloudfront_zone_id
    evaluate_target_health = false
  }
}

resource "aws_route53_record" "ops" {
  for_each = toset(["A", "AAAA"])

  zone_id = aws_route53_zone.platform.zone_id
  name    = "ops.${var.platform_domain}"
  type    = each.value

  alias {
    name                   = var.platform_admin_distribution_domain_name
    zone_id                = local.cloudfront_zone_id
    evaluate_target_health = false
  }
}

# --- Email: mail.<domain> -------------------------------------------------------------
#
# All tenants send from noreply@mail.<domain> with their own display name and
# Reply-To (the restaurant's address) - no DNS work per tenant. DKIM, a custom
# MAIL FROM and DMARC make that sender trustworthy to receiving mail servers.

resource "aws_sesv2_email_identity" "mail" {
  email_identity = local.mail_domain

  dkim_signing_attributes {
    next_signing_key_length = "RSA_2048_BIT"
  }

  tags = {
    Environment = var.environment
  }
}

resource "aws_route53_record" "dkim" {
  count = 3

  zone_id = aws_route53_zone.platform.zone_id
  name    = "${aws_sesv2_email_identity.mail.dkim_signing_attributes[0].tokens[count.index]}._domainkey.${local.mail_domain}"
  type    = "CNAME"
  ttl     = 1800
  records = ["${aws_sesv2_email_identity.mail.dkim_signing_attributes[0].tokens[count.index]}.dkim.amazonses.com"]
}

resource "aws_sesv2_email_identity_mail_from_attributes" "mail" {
  email_identity         = aws_sesv2_email_identity.mail.email_identity
  mail_from_domain       = "bounce.${local.mail_domain}"
  behavior_on_mx_failure = "USE_DEFAULT_VALUE"
}

resource "aws_route53_record" "mail_from_mx" {
  zone_id = aws_route53_zone.platform.zone_id
  name    = "bounce.${local.mail_domain}"
  type    = "MX"
  ttl     = 1800
  records = ["10 feedback-smtp.${data.aws_region.current.region}.amazonses.com"]
}

resource "aws_route53_record" "mail_from_spf" {
  zone_id = aws_route53_zone.platform.zone_id
  name    = "bounce.${local.mail_domain}"
  type    = "TXT"
  ttl     = 1800
  records = ["v=spf1 include:amazonses.com ~all"]
}

# Monitoring-only to start (p=none); tighten to quarantine once the reports
# show only SES sends as mail.<domain>.
resource "aws_route53_record" "dmarc" {
  zone_id = aws_route53_zone.platform.zone_id
  name    = "_dmarc.${local.mail_domain}"
  type    = "TXT"
  ttl     = 1800
  records = ["v=DMARC1; p=none;"]
}
