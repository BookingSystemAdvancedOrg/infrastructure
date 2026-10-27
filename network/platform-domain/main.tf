# Everything that needs a domain the platform owns. Created only when root
# var.platform_domain is set (count on the module call), so the rest of the
# stack deploys and works on *.cloudfront.net / execute-api URLs until the
# domain is decided.
#
#   <domain> hosted zone          delegate the domain to its name servers
#   *.<domain> + <domain> cert    ACM (us-east-1), DNS-validated in that zone
#   multi-tenant distribution     CloudFront SaaS Manager template serving
#                                 the shared customer site (customer-front-end
#                                 bucket) on every restaurant's own domain
#   connection group              the CNAME target customers point at
#   *.<domain>  -> connection group   only with var.tenant_subdomains_enabled
#                                 (<slug>.<domain>); off = own domains only
#   restaurang.<domain>          restaurant admin app (admin-front-end)
#   restaurant.<domain>          its first name - redirects to restaurang.
#   admin.<domain>               operator app (Booqy Console)
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
  # Restaurant websites on their own domains (multi-tenant distribution,
  # connection group) - off unless var.tenant_sites_enabled;
  # restaurant./admin./mail. never depend on them. <slug>.<domain> also needs
  # var.tenant_subdomains_enabled (the *.<domain> record).
  tenant_sites_count     = var.tenant_sites_enabled ? 1 : 0
  tenant_subdomain_count = var.tenant_sites_enabled && var.tenant_subdomains_enabled ? 1 : 0
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

# Subdomains answered by another account (prod delegates dev.<domain> to the
# dev account's zone). allow_overwrite adopts a record created by hand.
resource "aws_route53_record" "delegation" {
  for_each = var.subdomain_delegations

  zone_id         = aws_route53_zone.platform.zone_id
  name            = "${each.key}.${var.platform_domain}"
  type            = "NS"
  ttl             = 3600
  records         = each.value
  allow_overwrite = true
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

# --- CloudFront: multi-tenant distribution ------------------------------------

# Reads the customer-front-end bucket - the same build the public
# distribution serves. That bucket's policy admits this distribution.
resource "aws_cloudfront_origin_access_control" "tenant_sites" {
  count = local.tenant_sites_count

  name                              = "${local.prefix}tenant-sites-customer-site-oac"
  origin_access_control_origin_type = "s3"
  signing_behavior                  = "always"
  signing_protocol                  = "sigv4"
}

resource "aws_cloudfront_origin_access_control" "tenant_sites_menu_image" {
  count = local.tenant_sites_count

  name                              = "${local.prefix}tenant-sites-menu-image-oac"
  origin_access_control_origin_type = "s3"
  signing_behavior                  = "always"
  signing_protocol                  = "sigv4"
}

resource "aws_cloudfront_multitenant_distribution" "tenant_sites" {
  count = local.tenant_sites_count

  enabled             = true
  comment             = "${local.prefix}tenant websites (one distribution tenant per site/domain)"
  default_root_object = "index.html"
  http_version        = "http2and3"
  web_acl_id          = var.web_acl_arn != "" ? var.web_acl_arn : null

  # Each distribution tenant carries its tenantId (the workflows set it and
  # check it on resume). It picks the restaurant's own site folder
  # (sites/<tenantId>/, origin "tenant-site"); with var.per_tenant_sites off
  # every domain still gets the one shared build, which finds its restaurant
  # with GET /site-config?host=<the domain it was opened on>.
  tenant_config {
    parameter_definition {
      name = "tenantId"
      definition {
        string_schema {
          required = true
          comment  = "Tenant whose domain this distribution tenant serves"
        }
      }
    }
  }

  origin {
    id                       = "customer-site"
    domain_name              = var.customer_bucket_regional_domain_name
    origin_access_control_id = aws_cloudfront_origin_access_control.tenant_sites[0].id
  }

  origin {
    id                       = "menu-image"
    domain_name              = var.menu_image_bucket_regional_domain_name
    origin_access_control_id = aws_cloudfront_origin_access_control.tenant_sites_menu_image[0].id
  }

  # One site per restaurant (repo site-<slug>, deployed by its own role to
  # sites/<tenantId>/ in the sites bucket). The tenant parameter in the
  # origin path routes each distribution tenant to its own folder, so no
  # function and no per-tenant behaviour is needed. Same OAC: it signs for
  # any S3 origin; the sites bucket policy admits this distribution.
  dynamic "origin" {
    for_each = var.sites_bucket_regional_domain_name == "" ? [] : [1]
    content {
      id                       = "tenant-site"
      domain_name              = var.sites_bucket_regional_domain_name
      origin_path              = "/sites/{{tenantId}}"
      origin_access_control_id = aws_cloudfront_origin_access_control.tenant_sites[0].id
    }
  }

  # CachingOptimized honours the object's Cache-Control: every site deploy
  # (shared build and site-<slug> repos alike) uploads index.html as no-cache
  # and hashed assets as immutable, so a deploy is live without invalidating.
  default_cache_behavior {
    target_origin_id           = var.per_tenant_sites ? "tenant-site" : "customer-site"
    viewer_protocol_policy     = "redirect-to-https"
    cache_policy_id            = "658327ea-f89d-4fab-a63d-7e88639e58f6" # AWS managed "CachingOptimized"
    response_headers_policy_id = var.site_response_headers_policy_id
    compress                   = true

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

  # Inherited by <slug>.<domain> distribution tenants (when enabled). Customer
  # domains replace it with their own CloudFront-managed certificate.
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
# CNAME target customers set for their own domain (and the wildcard record
# below for <slug>.<domain> when subdomains are on).
resource "aws_cloudfront_connection_group" "tenant_sites" {
  count = local.tenant_sites_count

  name         = "${local.prefix}tenant-sites"
  enabled      = true
  ipv6_enabled = true

  tags = {
    Environment = var.environment
  }
}

resource "aws_route53_record" "tenant_sites_wildcard" {
  count = local.tenant_subdomain_count

  zone_id = aws_route53_zone.platform.zone_id
  name    = "*.${var.platform_domain}"
  type    = "CNAME"
  ttl     = 300
  records = [aws_cloudfront_connection_group.tenant_sites[0].routing_endpoint]
}

# --- Fixed hostnames for the two admin apps ---------------------------------------
# More specific than the wildcard, so they win over it.

# The admin app's first name (restaurant.<domain>). Kept as this resource,
# unchanged, so renaming the app to restaurang. never deletes and recreates
# this record (no DNS gap, no moved block). The distribution redirects it.
resource "aws_route53_record" "app" {
  for_each = toset(["A", "AAAA"])

  zone_id = aws_route53_zone.platform.zone_id
  name    = var.legacy_admin_app_hostname
  type    = each.value

  alias {
    name                   = var.admin_distribution_domain_name
    zone_id                = local.cloudfront_zone_id
    evaluate_target_health = false
  }
}

# restaurang.<domain> - the admin app's current name.
resource "aws_route53_record" "admin_app" {
  for_each = toset(["A", "AAAA"])

  zone_id = aws_route53_zone.platform.zone_id
  name    = var.admin_app_hostname
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
  name    = var.platform_admin_hostname
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
  # p=none: reports only, nothing is rejected yet.
  records = [var.dmarc_report_address == "" ? "v=DMARC1; p=none;" : "v=DMARC1; p=none; rua=mailto:${var.dmarc_report_address};"]
}
