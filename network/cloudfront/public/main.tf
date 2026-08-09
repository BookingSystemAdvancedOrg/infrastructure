locals {
  distribution_comment = var.environment == "prod" ? "public customer-facing distribution" : "${var.environment} public customer-facing distribution"
}

# Signs requests to the customer front-end asset bucket so CloudFront can
# read it directly - the bucket has all public access blocked, this is the
# only path in. One OAC per origin, not shared across distributions, so
# each distribution's access can be revoked independently later without
# touching the other.
resource "aws_cloudfront_origin_access_control" "customer_front_end_asset" {
  name                              = "${local.distribution_comment}-customer-front-end-asset-oac"
  origin_access_control_origin_type = "s3"
  signing_behavior                  = "always"
  signing_protocol                  = "sigv4"
}

# Same idea, separate OAC, for the menu-image bucket this distribution
# also reads from (the private distribution has its own separate OAC for
# the same bucket - see network/cloudfront/private).
resource "aws_cloudfront_origin_access_control" "menu_image" {
  name                              = "${local.distribution_comment}-menu-image-oac"
  origin_access_control_origin_type = "s3"
  signing_behavior                  = "always"
  signing_protocol                  = "sigv4"
}

resource "aws_cloudfront_distribution" "this" {
  enabled             = true
  is_ipv6_enabled     = true
  comment             = local.distribution_comment
  default_root_object = "index.html"

  # Sweden-based platform (same reasoning as the eu-north-1 region choice
  # for GDPR data residency) - no need to pay for edge locations on every
  # continent when the audience is regional. Easy to widen later.
  price_class = "PriceClass_100"

  origin {
    domain_name              = var.customer_bucket_regional_domain_name
    origin_id                = "customer-front-end-asset"
    origin_access_control_id = aws_cloudfront_origin_access_control.customer_front_end_asset.id
  }

  origin {
    domain_name              = var.menu_image_bucket_regional_domain_name
    origin_id                = "menu-image"
    origin_access_control_id = aws_cloudfront_origin_access_control.menu_image.id
  }

  # Everything not matched by a more specific behavior below goes to the
  # customer front-end SPA.
  default_cache_behavior {
    allowed_methods        = ["GET", "HEAD"]
    cached_methods         = ["GET", "HEAD"]
    target_origin_id       = "customer-front-end-asset"
    viewer_protocol_policy = "redirect-to-https"
    cache_policy_id        = "658327ea-f89d-4fab-a63d-7e88639e58f6" # AWS managed "CachingOptimized"
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

  # This is an SPA with client-side routing - S3 has no object at, say,
  # /reservations/123, only at index.html. Without this, refreshing any
  # non-root route would 403/404 instead of loading the app and letting
  # its own router take over.
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

  # No ACM certificate yet (on hold) - launches on the default
  # *.cloudfront.net domain. Swap this for viewer_certificate.acm_certificate_arn
  # once a cert exists, same approach already used for API Gateway's
  # default execute-api endpoint.
  viewer_certificate {
    cloudfront_default_certificate = true
  }

  tags = {
    Environment = var.environment
  }
}
