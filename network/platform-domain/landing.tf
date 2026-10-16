# Public page on the bare domain (<domain> and www.<domain>): what Booqy is,
# contact, privacy policy and terms. A static site in a private bucket behind
# its own CloudFront distribution, served with the wildcard certificate (its
# SANs cover <domain>). The pages live in ./landing and are rendered here -
# a change to them is a normal infrastructure change, no separate pipeline.
#
# AWS reviews this page before granting SES production access (emailing any
# customer), so it must stay public and describe the service and contact.

locals {
  landing_pages = {
    "index.html"      = { template = "index.html.tftpl", title = "Booqy – bordsbokning, beställningar och catering för restauranger", path = "/" }
    "integritet.html" = { template = "integritet.html.tftpl", title = "Integritetspolicy – Booqy", path = "/integritet.html" }
    "villkor.html"    = { template = "villkor.html.tftpl", title = "Villkor – Booqy", path = "/villkor.html" }
    "404.html"        = { template = "404.html.tftpl", title = "Sidan finns inte – Booqy", path = "/404.html" }
  }
  landing_vars = {
    domain        = var.platform_domain
    admin_host    = var.admin_app_hostname
    contact_email = var.landing_contact_email
    company       = var.landing_company
    updated       = var.landing_updated
  }
  landing_html = {
    for key, page in local.landing_pages : key => templatefile("${path.module}/landing/layout.html.tftpl", merge(local.landing_vars, {
      title       = page.title
      description = "Booqy är ett bokningssystem för svenska restauranger: bordsbokning, matbeställning och catering på restaurangens egen webbplats."
      path        = page.path
      year        = substr(var.landing_updated, -4, 4)
      body        = templatefile("${path.module}/landing/${page.template}", local.landing_vars)
    }))
  }
  # Short cache so a text change is live within minutes without invalidations.
  landing_cache_control = "public, max-age=300"
}

resource "aws_s3_bucket" "landing" {
  bucket        = "${local.prefix}landing-${data.aws_caller_identity.current.account_id}"
  force_destroy = true # only rendered copies of ./landing live here

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

resource "aws_s3_object" "landing_page" {
  for_each = local.landing_html

  bucket        = aws_s3_bucket.landing.id
  key           = each.key
  content       = each.value
  content_type  = "text/html; charset=utf-8"
  cache_control = local.landing_cache_control
  etag          = md5(each.value)
}

resource "aws_s3_object" "landing_asset" {
  for_each = {
    "site.css"    = "text/css; charset=utf-8"
    "favicon.svg" = "image/svg+xml"
  }

  bucket        = aws_s3_bucket.landing.id
  key           = each.key
  source        = "${path.module}/landing/${each.key}"
  content_type  = each.value
  cache_control = local.landing_cache_control
  etag          = filemd5("${path.module}/landing/${each.key}")
}

resource "aws_cloudfront_origin_access_control" "landing" {
  name                              = "${local.prefix}landing-oac"
  origin_access_control_origin_type = "s3"
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
