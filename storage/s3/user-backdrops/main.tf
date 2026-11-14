# Each signed-in user's background image library (blurred behind the glass
# UI in Booqy Admin and Booqy Console), up to 20 images per user:
#
#   admin/<tenantId>/<sub>/backdrops/<id>[.thumb.webp]   Booqy Admin (user-backdrop)
#   console/<sub>/backdrops/<id>[.thumb.webp]            Booqy Console (platform-tenants)
#
# The items (and which image is selected) are in the user-backdrops table
# (storage/dynamodb/user-backdrops). The browser uploads straight here with
# a presigned POST (JPEG, PNG or WebP, max 10 MB, exact key and
# Content-Type); the Lambda then writes a WebP thumbnail. Images are shown
# through one-hour presigned GETs. Deleted by the user, with the user
# (manage-user, operator deletion) and with the restaurant (tenant-purge).
# Private, TLS-only, encrypted, no versioning. The first version kept one
# image at .../backdrop; the Lambdas move it into the library.

data "aws_caller_identity" "current" {}

resource "aws_s3_bucket" "this" {
  bucket = var.environment == "prod" ? "user-backdrops-${data.aws_caller_identity.current.account_id}" : "${var.environment}-user-backdrops-${data.aws_caller_identity.current.account_id}"

  # Dev only: lets the environment be torn down with images still in it.
  force_destroy = var.environment != "prod"

  tags = {
    Environment = var.environment
  }
}

resource "aws_s3_bucket_public_access_block" "this" {
  bucket = aws_s3_bucket.this.id

  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

resource "aws_s3_bucket_ownership_controls" "this" {
  bucket = aws_s3_bucket.this.id

  rule {
    object_ownership = "BucketOwnerEnforced"
  }
}

resource "aws_s3_bucket_server_side_encryption_configuration" "this" {
  bucket = aws_s3_bucket.this.id

  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm = "AES256"
    }
  }
}

resource "aws_s3_bucket_lifecycle_configuration" "this" {
  bucket = aws_s3_bucket.this.id

  rule {
    id     = "abort-incomplete-uploads"
    status = "Enabled"

    filter {}

    abort_incomplete_multipart_upload {
      days_after_initiation = 1
    }
  }
}

# Presigned POST uploads from the admin app and the console (the desktop app
# loads the same origins). GET too, for a page that reads the image with
# fetch() instead of an <img> or CSS background.
resource "aws_s3_bucket_cors_configuration" "this" {
  bucket = aws_s3_bucket.this.id

  cors_rule {
    allowed_methods = ["POST", "GET"]
    allowed_origins = var.allowed_origins
    allowed_headers = ["*"]
    max_age_seconds = 3000
  }
}

resource "aws_s3_bucket_policy" "this" {
  bucket = aws_s3_bucket.this.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid       = "DenyInsecureTransport"
        Effect    = "Deny"
        Principal = "*"
        Action    = "s3:*"
        Resource  = [aws_s3_bucket.this.arn, "${aws_s3_bucket.this.arn}/*"]
        Condition = {
          Bool = { "aws:SecureTransport" = "false" }
        }
      }
    ]
  })

  depends_on = [aws_s3_bucket_public_access_block.this]
}
