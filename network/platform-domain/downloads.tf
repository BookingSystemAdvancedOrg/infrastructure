# Desktop app installers (admin-front-end/desktop and booqy-console/desktop):
# https://<domain>/downloads/<app>/latest/<file> plus versioned copies and
# latest.json, which the desktop shell reads to offer "Uppdatera". Served by
# the landing distribution under /downloads/* from its own private bucket, so
# booqy-website's "s3 sync --delete" never touches it. The two app repos
# upload through security/iam/oidc/desktop-release-role (put only, no
# delete). Installers are rebuildable from git, so force_destroy is fine.

resource "aws_s3_bucket" "downloads" {
  bucket        = "${local.prefix}desktop-downloads-${data.aws_caller_identity.current.account_id}"
  force_destroy = true

  tags = {
    Environment = var.environment
  }
}

resource "aws_s3_bucket_public_access_block" "downloads" {
  bucket = aws_s3_bucket.downloads.id

  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

resource "aws_s3_bucket_ownership_controls" "downloads" {
  bucket = aws_s3_bucket.downloads.id

  rule {
    object_ownership = "BucketOwnerEnforced"
  }
}

resource "aws_s3_bucket_server_side_encryption_configuration" "downloads" {
  bucket = aws_s3_bucket.downloads.id

  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm = "AES256"
    }
  }
}

# Versions under downloads/versions/ stay (latest.json points at them); a
# build only happens when desktop/ changes, so this grows slowly.
resource "aws_s3_bucket_lifecycle_configuration" "downloads" {
  bucket = aws_s3_bucket.downloads.id

  rule {
    id     = "abort-incomplete-uploads"
    status = "Enabled"

    filter {}

    abort_incomplete_multipart_upload {
      days_after_initiation = 1
    }
  }
}

resource "aws_s3_bucket_policy" "downloads" {
  bucket = aws_s3_bucket.downloads.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid       = "AllowLandingDistributionReadOnly"
        Effect    = "Allow"
        Principal = { Service = "cloudfront.amazonaws.com" }
        Action    = "s3:GetObject"
        Resource  = "${aws_s3_bucket.downloads.arn}/*"
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
        Resource  = [aws_s3_bucket.downloads.arn, "${aws_s3_bucket.downloads.arn}/*"]
        Condition = {
          Bool = { "aws:SecureTransport" = "false" }
        }
      }
    ]
  })

  depends_on = [aws_s3_bucket_public_access_block.downloads]
}

resource "aws_cloudfront_origin_access_control" "downloads" {
  name                              = "${local.prefix}desktop-downloads-oac"
  origin_access_control_origin_type = "s3"
  signing_behavior                  = "always"
  signing_protocol                  = "sigv4"
}
