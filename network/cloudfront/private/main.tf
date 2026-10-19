locals {
  distribution_comment = var.environment == "prod" ? "private staff-facing distribution" : "${var.environment} private staff-facing distribution"
}

# Signs requests to the admin front-end asset bucket so CloudFront can
# read it directly - the bucket has all public access blocked, this is the
# only path in. One OAC per origin, not shared across distributions, so
# each distribution's access can be revoked independently later without
# touching the other.
resource "aws_cloudfront_origin_access_control" "admin_front_end_asset" {
  name                              = "${local.distribution_comment}-admin-fe-oac"
  origin_access_control_origin_type = "s3"
  signing_behavior                  = "always"
  signing_protocol                  = "sigv4"
}

# Same idea, separate OAC, for the menu-image bucket this distribution
# also reads from (the public distribution has its own separate OAC for
# the same bucket - see network/cloudfront/public).
resource "aws_cloudfront_origin_access_control" "menu_image" {
  name                              = "${local.distribution_comment}-menu-image-oac"
  origin_access_control_origin_type = "s3"
  signing_behavior                  = "always"
  signing_protocol                  = "sigv4"
}

locals {
  name_prefix = var.environment == "prod" ? "" : "${var.environment}-"
  menu_bucket = split(".", var.menu_image_bucket_regional_domain_name)[0]

  # The admin app's Content Security Policy. Everything is self-hosted
  # (scripts, styles, fonts) and the API is same-origin under /api, so
  # 'self' covers almost all of it. Exceptions:
  #   - img-src https: menu photos come from the public distribution's
  #     domain; blob:/data: for the image preview before upload and QR codes
  #   - connect-src: the menu-image bucket, for presigned PUT uploads
  #   - style-src 'unsafe-inline': React style={{}} attributes
  admin_csp = join("; ", [
    "default-src 'self'",
    "script-src 'self'",
    "style-src 'self' 'unsafe-inline'",
    "img-src 'self' data: blob: https:",
    "font-src 'self'",
    "connect-src 'self' https://${local.menu_bucket}.s3.eu-north-1.amazonaws.com https://${local.menu_bucket}.s3.amazonaws.com",
    "worker-src 'self' blob:",
    "object-src 'none'",
    "base-uri 'self'",
    "form-action 'self'",
    "frame-ancestors 'none'",
  ])
}

resource "aws_cloudfront_function" "spa_routing" {
  name    = "${local.name_prefix}admin-spa-routing"
  runtime = "cloudfront-js-2.0"
  comment = "Admin app: client-side routes load /index.html"
  publish = true
  code    = file("${path.module}/functions/spa-routing.js")
}

resource "aws_cloudfront_function" "api_proxy" {
  name    = "${local.name_prefix}admin-api-proxy"
  runtime = "cloudfront-js-2.0"
  comment = "Admin app /api/*: strip prefix, pass viewer IP and host"
  publish = true
  code    = file("${path.module}/functions/api-proxy.js")
}

# Security headers for everything the admin app serves: HSTS, no sniffing,
# no framing (clickjacking), a strict referrer policy and the CSP above.
resource "aws_cloudfront_response_headers_policy" "admin" {
  name    = "${local.name_prefix}admin-app-security-headers"
  comment = "Admin app: CSP, HSTS, no framing"

  security_headers_config {
    content_security_policy {
      content_security_policy = local.admin_csp
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
      override        = true
    }
    strict_transport_security {
      access_control_max_age_sec = 63072000
      include_subdomains         = false
      preload                    = false
      override                   = true
    }
  }
}

# The API's own answers: same hardening minus the page-level CSP, plus
# no-store so no browser or proxy keeps a token response around.
resource "aws_cloudfront_response_headers_policy" "api" {
  name    = "${local.name_prefix}admin-api-security-headers"
  comment = "Admin app /api/*: HSTS, nosniff, no framing"

  security_headers_config {
    content_type_options {
      override = true
    }
    frame_options {
      frame_option = "DENY"
      override     = true
    }
    referrer_policy {
      referrer_policy = "no-referrer"
      override        = true
    }
    strict_transport_security {
      access_control_max_age_sec = 63072000
      include_subdomains         = false
      preload                    = false
      override                   = true
    }
  }
}

resource "aws_cloudfront_distribution" "this" {
  enabled             = true
  is_ipv6_enabled     = true
  comment             = local.distribution_comment
  default_root_object = "index.html"

  # restaurant.<platform domain> once the platform domain is set - one shared admin
  # app for every tenant (who you are comes from your login, not the URL).
  aliases = var.aliases

  # Sweden-based platform (same reasoning as the eu-north-1 region choice
  # for GDPR data residency) - no need to pay for edge locations on every
  # continent when the audience is regional. Easy to widen later.
  price_class = "PriceClass_100"

  origin {
    domain_name              = var.admin_bucket_regional_domain_name
    origin_id                = "admin-front-end-asset"
    origin_access_control_id = aws_cloudfront_origin_access_control.admin_front_end_asset.id
  }

  origin {
    domain_name              = var.menu_image_bucket_regional_domain_name
    origin_id                = "menu-image"
    origin_access_control_id = aws_cloudfront_origin_access_control.menu_image.id
  }

  # The backend API, served under /api on the admin app's own address so the
  # app is same-origin with it: the refresh token can live in an HttpOnly
  # cookie scoped to this host, and the app needs no CORS.
  origin {
    domain_name = var.api_origin_domain
    origin_id   = "api"

    custom_origin_config {
      http_port              = 80
      https_port             = 443
      origin_protocol_policy = "https-only"
      origin_ssl_protocols   = ["TLSv1.2"]
    }

    # Proves to the API that the viewer IP/host headers came from here.
    custom_header {
      name  = "x-booqy-edge"
      value = var.edge_secret
    }
  }

  # Everything not matched by a more specific behavior below goes to the
  # restaurant admin SPA (owners + staff of every tenant).
  default_cache_behavior {
    allowed_methods            = ["GET", "HEAD"]
    cached_methods             = ["GET", "HEAD"]
    target_origin_id           = "admin-front-end-asset"
    viewer_protocol_policy     = "redirect-to-https"
    cache_policy_id            = "658327ea-f89d-4fab-a63d-7e88639e58f6" # AWS managed "CachingOptimized"
    response_headers_policy_id = aws_cloudfront_response_headers_policy.admin.id
    compress                   = true

    function_association {
      event_type   = "viewer-request"
      function_arn = aws_cloudfront_function.spa_routing.arn
    }
  }

  ordered_cache_behavior {
    path_pattern           = "/api/*"
    target_origin_id       = "api"
    viewer_protocol_policy = "https-only"
    allowed_methods        = ["DELETE", "GET", "HEAD", "OPTIONS", "PATCH", "POST", "PUT"]
    cached_methods         = ["GET", "HEAD"]
    compress               = false
    cache_policy_id        = "4135ea2d-6df8-44a3-9df3-4b5a84be39ad" # AWS managed "CachingDisabled"
    # All viewer headers (Authorization, cookies, Origin) except Host: API
    # Gateway's default endpoint rejects a foreign Host.
    origin_request_policy_id   = "b689b0a8-53d0-40ab-baf2-68738e2966ac" # AWS managed "AllViewerExceptHostHeader"
    response_headers_policy_id = aws_cloudfront_response_headers_policy.api.id

    function_association {
      event_type   = "viewer-request"
      function_arn = aws_cloudfront_function.api_proxy.arn
    }
  }

  # Menu images live under this bucket's objects at the same path they're
  # requested at (e.g. a request for /menu-images/foo.jpg maps to the
  # object key menu-images/foo.jpg) - keep application uploads under that
  # prefix to match.
  ordered_cache_behavior {
    path_pattern           = "/menu-images/*"
    allowed_methods        = ["GET", "HEAD"]
    cached_methods         = ["GET", "HEAD"]
    target_origin_id       = "menu-image"
    viewer_protocol_policy = "redirect-to-https"
    cache_policy_id        = "658327ea-f89d-4fab-a63d-7e88639e58f6" # AWS managed "CachingOptimized"
  }

  # SPA routing is the spa_routing function on the default behavior, not
  # custom_error_response: error pages apply to every behavior and would
  # rewrite the API's 403/404 answers into index.html.

  restrictions {
    geo_restriction {
      restriction_type = "none"
    }
  }

  # Default *.cloudfront.net certificate until the platform domain is set;
  # then the platform's wildcard certificate (network/platform-domain) for
  # restaurant.<domain>.
  viewer_certificate {
    cloudfront_default_certificate = var.acm_certificate_arn == ""
    acm_certificate_arn            = var.acm_certificate_arn == "" ? null : var.acm_certificate_arn
    ssl_support_method             = var.acm_certificate_arn == "" ? null : "sni-only"
    minimum_protocol_version       = var.acm_certificate_arn == "" ? "TLSv1" : "TLSv1.2_2021"
  }

  tags = {
    Environment = var.environment
  }
}
