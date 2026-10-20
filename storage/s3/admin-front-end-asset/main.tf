
# S3 bucket names are globally unique across every AWS account, not just
# this one - the account ID suffix guarantees no collision without needing
# a manually-chosen unique name per account.
data "aws_caller_identity" "current" {}

resource "aws_s3_bucket" "admin_front_end_asset" {
  bucket = var.environment == "prod" ? "admin-front-end-asset-${data.aws_caller_identity.current.account_id}" : "${var.environment}-admin-front-end-asset-${data.aws_caller_identity.current.account_id}"

  tags = {
    Environment = var.environment
  }
}

resource "aws_s3_bucket_public_access_block" "admin_front_end_asset" {
  bucket = aws_s3_bucket.admin_front_end_asset.id

  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

# Only the private CloudFront distribution's OAC is allowed to read this
# bucket - scoped via AWS:SourceArn to that one distribution's ARN, not to
# every distribution in the account. Public access is fully blocked above,
# so this policy is the only way anything can ever read these objects.
resource "aws_s3_bucket_policy" "admin_front_end_asset" {
  bucket = aws_s3_bucket.admin_front_end_asset.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid       = "AllowPrivateCloudFrontReadOnly"
        Effect    = "Allow"
        Principal = { Service = "cloudfront.amazonaws.com" }
        Action    = "s3:GetObject"
        Resource  = "${aws_s3_bucket.admin_front_end_asset.arn}/*"
        Condition = {
          StringEquals = {
            "AWS:SourceArn" = "${var.cloudfront_distribution_arn}"
          }
        }
      }
    ]
  })
}

# Every deploy overwrites index.html and deletes the previous build's hashed
# assets (s3 sync --delete). With versioning on, the previous build is still
# there as noncurrent versions for var.noncurrent_version_days, so a bad
# release can be undone by redeploying the previous commit (the "Redeploy a
# commit" workflow, docs/RELEASES.md) and nothing is lost in between.
resource "aws_s3_bucket_versioning" "admin_front_end_asset" {
  bucket = aws_s3_bucket.admin_front_end_asset.id

  versioning_configuration {
    status = "Enabled"
  }
}

# Old builds are not kept forever: noncurrent versions expire after
# var.noncurrent_version_days, and the delete markers s3 sync --delete
# leaves behind are removed once nothing is under them.
resource "aws_s3_bucket_lifecycle_configuration" "admin_front_end_asset" {
  bucket = aws_s3_bucket.admin_front_end_asset.id

  rule {
    id     = "expire-previous-builds"
    status = "Enabled"

    filter {}

    noncurrent_version_expiration {
      noncurrent_days = var.noncurrent_version_days
    }

    expiration {
      expired_object_delete_marker = true
    }

    abort_incomplete_multipart_upload {
      days_after_initiation = 7
    }
  }

  depends_on = [aws_s3_bucket_versioning.admin_front_end_asset]
}
