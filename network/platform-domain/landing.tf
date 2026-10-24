# Public page on the bare domain (<domain> and www.<domain>): what Booqy is,
# contact, privacy policy and terms. A static site in a private bucket behind
# its own CloudFront distribution, served with the wildcard certificate (its
# SANs cover <domain>). Terraform owns the hosting only; the pages live in
# the booqy-website repo, which deploys them through its own OIDC role
# (security/iam/oidc/website-deploy-role): sync to this bucket, invalidate
# this distribution.
#
# AWS reviews this page before granting SES production access (emailing any
# customer), so it must stay public and describe the service and contact.

# The pages used to be rendered and uploaded here. Forget those objects
# without deleting them, so the site stays up until booqy-website's first
# deploy replaces them.
removed {
  from = aws_s3_object.landing_page
  lifecycle {
    destroy = false
  }
}

removed {
  from = aws_s3_object.landing_asset
  lifecycle {
    destroy = false
  }
}

resource "aws_s3_bucket" "landing" {
  bucket        = "${local.prefix}landing-${data.aws_caller_identity.current.account_id}"
  force_destroy = true # only build output of booqy-website lives here (redeployable)

  tags = {
    Environment = var.environment
  }
}

resource "aws_s3_bucket_public_access_block" "landing" {
  bucket = aws_s3_bucket.landing.id

  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

resource "aws_s3_bucket_ownership_controls" "landing" {
  bucket = aws_s3_bucket.landing.id

  rule {
    object_ownership = "BucketOwnerEnforced"
  }
}

resource "aws_s3_bucket_server_side_encryption_configuration" "landing" {
  bucket = aws_s3_bucket.landing.id

  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm = "AES256"
    }
  }
}

resource "aws_s3_bucket_policy" "landing" {
  bucket = aws_s3_bucket.landing.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid       = "AllowLandingDistributionReadOnly"
        Effect    = "Allow"
        Principal = { Service = "cloudfront.amazonaws.com" }
        Action    = "s3:GetObject"
        Resource  = "${aws_s3_bucket.landing.arn}/*"
        Condition = {
          StringEquals = {
            "AWS:SourceArn" = aws_cloudfront_distribution.landing.arn
          }
        }
      },
      {
        Sid       = "DenyInsecureTransport"
        Effect    = "Deny"
        Principal = "*"
        Action    = "s3:*"
        Resource  = [aws_s3_bucket.landing.arn, "${aws_s3_bucket.landing.arn}/*"]
        Condition = {
          Bool = { "aws:SecureTransport" = "false" }
        }
      }
    ]
  })

  depends_on = [aws_s3_bucket_public_access_block.landing]
}

resource "aws_cloudfront_origin_access_control" "landing" {
  name                              = "${local.prefix}landing-oac"
  origin_access_control_origin_type = "s3"
  signing_behavior                  = "always"
  signing_protocol                  = "sigv4"
}

# "Boka en demo" (booqy-website /demo): POST /api/demo-request goes to the
# demo-request Lambda's function URL (compute/lambda/demo-request). OAC signs
# each request so the URL (AWS_IAM) only accepts calls through this
# distribution. Lambda URLs need the body hash on POST - the page sends it as
# x-amz-content-sha256.
resource "aws_cloudfront_origin_access_control" "demo_request" {
  count                             = var.demo_request_enabled ? 1 : 0
  name                              = "${local.prefix}landing-demo-request-oac"
  origin_access_control_origin_type = "lambda"
  signing_behavior                  = "always"
  signing_protocol                  = "sigv4"
}

# Cookieless statistics (site-analytics/): GET /api/collect goes to the
# site-analytics Lambda's function URL, OAC-signed like demo-request. GET
# only, so no body hash is needed and the beacon works with keepalive on
# page hide. The origin request policy also hands over CloudFront's viewer
# country, region and city, which is all the location the statistics keep.
resource "aws_cloudfront_origin_access_control" "site_analytics" {
  count                             = var.site_analytics_enabled ? 1 : 0
  name                              = "${local.prefix}landing-site-analytics-oac"
  origin_access_control_origin_type = "lambda"
  signing_behavior                  = "always"
  signing_protocol                  = "sigv4"
}

resource "aws_cloudfront_distribution" "landing" {
  enabled             = true
  comment             = "${local.prefix}public page on ${var.platform_domain}"
  aliases             = [var.platform_domain, "www.${var.platform_domain}"]
  default_root_object = "index.html"
  http_version        = "http2and3"
  is_ipv6_enabled     = true
  price_class         = "PriceClass_100"

  origin {
    origin_id                = "landing"
    domain_name              = aws_s3_bucket.landing.bucket_regional_domain_name
    origin_access_control_id = aws_cloudfront_origin_access_control.landing.id
  }

  dynamic "origin" {
    for_each = var.demo_request_enabled ? [1] : []
    content {
      origin_id                = "demo-request"
      domain_name              = var.demo_request_origin_domain
      origin_access_control_id = aws_cloudfront_origin_access_control.demo_request[0].id

      custom_origin_config {
        http_port              = 80
        https_port             = 443
        origin_protocol_policy = "https-only"
        origin_ssl_protocols   = ["TLSv1.2"]
      }
    }
  }

  dynamic "origin" {
    for_each = var.site_analytics_enabled ? [1] : []
    content {
      origin_id                = "site-analytics"
      domain_name              = var.site_analytics_origin_domain
      origin_access_control_id = aws_cloudfront_origin_access_control.site_analytics[0].id

      custom_origin_config {
        http_port              = 80
        https_port             = 443
        origin_protocol_policy = "https-only"
        origin_ssl_protocols   = ["TLSv1.2"]
      }
    }
  }

  # Before /api/* (behaviours match in order).
  dynamic "ordered_cache_behavior" {
    for_each = var.site_analytics_enabled ? [1] : []
    content {
      path_pattern             = "/api/collect"
      target_origin_id         = "site-analytics"
      viewer_protocol_policy   = "https-only"
      allowed_methods          = ["GET", "HEAD"]
      cached_methods           = ["GET", "HEAD"]
      compress                 = false
      cache_policy_id          = "4135ea2d-6df8-44a3-9df3-4b5a84be39ad" # AWS managed "CachingDisabled"
      origin_request_policy_id = "b689b0a8-53d0-40ab-baf2-68738e2966ac" # AWS managed "AllViewerExceptHostHeader" (+ viewer location headers)
    }
  }

  dynamic "ordered_cache_behavior" {
    for_each = var.demo_request_enabled ? [1] : []
    content {
      path_pattern           = "/api/*"
      target_origin_id       = "demo-request"
      viewer_protocol_policy = "https-only"
      allowed_methods        = ["DELETE", "GET", "HEAD", "OPTIONS", "PATCH", "POST", "PUT"]
      cached_methods         = ["GET", "HEAD"]
      compress               = false
      cache_policy_id        = "4135ea2d-6df8-44a3-9df3-4b5a84be39ad" # AWS managed "CachingDisabled"
      # Everything but Host (a Lambda URL rejects a foreign Host header).
      origin_request_policy_id = "b689b0a8-53d0-40ab-baf2-68738e2966ac" # AWS managed "AllViewerExceptHostHeader"
    }
  }

  default_cache_behavior {
    target_origin_id           = "landing"
    viewer_protocol_policy     = "redirect-to-https"
    allowed_methods            = ["GET", "HEAD"]
    cached_methods             = ["GET", "HEAD"]
    compress                   = true
    cache_policy_id            = "658327ea-f89d-4fab-a63d-7e88639e58f6" # AWS managed "CachingOptimized"
    response_headers_policy_id = "67f7725c-6f97-4210-82d7-5512b31e9d03" # AWS managed "SecurityHeadersPolicy"
  }

  # Unknown paths: S3 answers 403 through OAC (no ListBucket) - show 404.html.
  custom_error_response {
    error_code            = 403
    response_code         = 404
    response_page_path    = "/404.html"
    error_caching_min_ttl = 60
  }

  custom_error_response {
    error_code            = 404
    response_code         = 404
    response_page_path    = "/404.html"
    error_caching_min_ttl = 60
  }

  restrictions {
    geo_restriction {
      restriction_type = "none"
    }
  }

  viewer_certificate {
    acm_certificate_arn      = aws_acm_certificate_validation.wildcard.certificate_arn
    ssl_support_method       = "sni-only"
    minimum_protocol_version = "TLSv1.2_2021"
  }

  tags = {
    Environment = var.environment
  }
}

resource "aws_route53_record" "landing" {
  for_each = {
    for pair in setproduct([var.platform_domain, "www.${var.platform_domain}"], ["A", "AAAA"]) :
    "${pair[0]}/${pair[1]}" => { name = pair[0], type = pair[1] }
  }

  zone_id = aws_route53_zone.platform.zone_id
  name    = each.value.name
  type    = each.value.type

  alias {
    name                   = aws_cloudfront_distribution.landing.domain_name
    zone_id                = local.cloudfront_zone_id
    evaluate_target_health = false
  }
}
