locals {
  distribution_comment = var.environment == "prod" ? "platform operator app distribution" : "${var.environment} platform operator app distribution"
}

# Hosts the platform admin (operator) SPA - where you create and manage
# tenants. Same shape as the restaurant admin distribution minus the menu
# images, plus strict security headers: this app can provision customers,
# so it gets HSTS, no framing, no MIME sniffing and a tight referrer policy.

resource "aws_cloudfront_origin_access_control" "this" {
  name                              = "${local.distribution_comment}-oac"
  origin_access_control_origin_type = "s3"
  signing_behavior                  = "always"
  signing_protocol                  = "sigv4"
}

# The managed SecurityHeadersPolicy plus a Content Security Policy: the
# Console holds operator tokens in sessionStorage, so the CSP is what keeps
# injected script from loading or sending them anywhere.
resource "aws_cloudfront_response_headers_policy" "this" {
  name    = "${var.environment == "prod" ? "" : "${var.environment}-"}console-security-headers"
  comment = "Booqy Console: CSP, HSTS, no framing"

  security_headers_config {
    content_security_policy {
      content_security_policy = join("; ", [
        "default-src 'self'",
        "script-src 'self'",
        "style-src 'self' 'unsafe-inline'",
        "img-src 'self' data:",
        "font-src 'self'",
        "connect-src 'self' https://cognito-idp.${var.region}.amazonaws.com ${var.api_origin} https://${var.upload_bucket_name}.s3.${var.region}.amazonaws.com https://${var.upload_bucket_name}.s3.amazonaws.com",
        "object-src 'none'",
        "base-uri 'self'",
        "form-action 'self'",
        "frame-ancestors 'none'",
      ])
      override = true
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

resource "aws_cloudfront_distribution" "this" {
  enabled             = true
  is_ipv6_enabled     = true
  comment             = local.distribution_comment
  default_root_object = "index.html"
  price_class         = "PriceClass_100"

  # admin.<platform domain> once the platform domain is set.
  aliases = var.aliases

  origin {
    domain_name              = var.bucket_regional_domain_name
    origin_id                = "platform-admin-front-end-asset"
    origin_access_control_id = aws_cloudfront_origin_access_control.this.id
  }

  default_cache_behavior {
    allowed_methods            = ["GET", "HEAD"]
    cached_methods             = ["GET", "HEAD"]
    target_origin_id           = "platform-admin-front-end-asset"
    viewer_protocol_policy     = "redirect-to-https"
    cache_policy_id            = "658327ea-f89d-4fab-a63d-7e88639e58f6" # AWS managed "CachingOptimized"
    response_headers_policy_id = aws_cloudfront_response_headers_policy.this.id
    compress                   = true
  }

  # SPA client-side routing (/auth/callback, /tenants/123, ...).
  custom_error_response {
    error_code         = 403
    response_code      = 200
    response_page_path = "/index.html"
  }

  custom_error_response {
    error_code         = 404
    response_code      = 200
    response_page_path = "/index.html"
  }

  restrictions {
    geo_restriction {
      restriction_type = "none"
    }
  }

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
