# Dev mail outbox: while the platform's sending domain isn't verified in SES
# (booqy.se), the notification Lambda saves every email it would have sent
# here instead - as JSON (to, from, reply-to, subject, text, html) - and the
# operator console (Booqy Console, "Mail outbox") lists and shows them. That way
# receipts, offers, confirmations and their links can be checked in dev
# without SES.
#
# Never created in prod (count on the module call + validation on
# var.mail_outbox). Messages contain test guests' names, emails and phone
# numbers, so the bucket is private, TLS-only and everything expires after
# 30 days.
#
# Keys: outbox/<inverted epoch ms, 13 digits>-<random id>.json - S3 lists
# keys in ascending order, so the inverted timestamp makes the newest
# message come first without listing the whole bucket.

data "aws_caller_identity" "current" {}

resource "aws_s3_bucket" "mail_outbox" {
  bucket = "${var.environment}-mail-outbox-${data.aws_caller_identity.current.account_id}"

  # Test data only - the bucket can be torn down with what's in it.
  force_destroy = true

  tags = {
    Environment = var.environment
  }
}

resource "aws_s3_bucket_public_access_block" "mail_outbox" {
  bucket = aws_s3_bucket.mail_outbox.id

  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

resource "aws_s3_bucket_ownership_controls" "mail_outbox" {
  bucket = aws_s3_bucket.mail_outbox.id

  rule {
    object_ownership = "BucketOwnerEnforced"
  }
}

resource "aws_s3_bucket_server_side_encryption_configuration" "mail_outbox" {
  bucket = aws_s3_bucket.mail_outbox.id

  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm = "AES256"
    }
  }
}

resource "aws_s3_bucket_lifecycle_configuration" "mail_outbox" {
  bucket = aws_s3_bucket.mail_outbox.id

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

resource "aws_s3_bucket_policy" "mail_outbox" {
  bucket = aws_s3_bucket.mail_outbox.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid       = "DenyInsecureTransport"
        Effect    = "Deny"
        Principal = "*"
        Action    = "s3:*"
        Resource = [
          aws_s3_bucket.mail_outbox.arn,
          "${aws_s3_bucket.mail_outbox.arn}/*",
        ]
        Condition = {
          Bool = { "aws:SecureTransport" = "false" }
        }
      }
    ]
  })

  depends_on = [aws_s3_bucket_public_access_block.mail_outbox]
}
