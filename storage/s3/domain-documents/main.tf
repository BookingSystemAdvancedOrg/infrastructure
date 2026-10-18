# Registreringsbevis (registration certificates) uploaded in Booqy Console
# when a restaurant's AB buys a .se domain: the .se registry verifies the
# owner through an AWS Support case before the domain goes live (NIS2).
#
# The browser uploads straight here with a presigned POST from the
# platform-tenants Lambda (PDF, max 10 MB, keys tenants/<tenantId>/...). The
# Lambda deletes a file once the registration has gone through; anything
# left is expired after 30 days - company documents are kept no longer than
# the verification needs. Private, TLS-only, encrypted.

data "aws_caller_identity" "current" {}

resource "aws_s3_bucket" "this" {
  bucket = var.environment == "prod" ? "domain-documents-${data.aws_caller_identity.current.account_id}" : "${var.environment}-domain-documents-${data.aws_caller_identity.current.account_id}"

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
    id     = "expire-after-30-days"
    status = "Enabled"

    filter {}

    expiration {
      days = 30
    }

    abort_incomplete_multipart_upload {
      days_after_initiation = 1
    }
  }
}

# Presigned POST from the operator console only. Downloads are presigned GET
# links opened as a normal navigation, so they need no CORS.
resource "aws_s3_bucket_cors_configuration" "this" {
  bucket = aws_s3_bucket.this.id

  cors_rule {
    allowed_methods = ["POST"]
    allowed_origins = var.allowed_origins
    allowed_headers = ["*"]
    max_age_seconds = 300
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
