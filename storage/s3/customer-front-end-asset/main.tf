
# S3 bucket names are globally unique across every AWS account, not just
# this one - the account ID suffix guarantees no collision without needing
# a manually-chosen unique name per fork/customer.
data "aws_caller_identity" "current" {}

resource "aws_s3_bucket" "customer_front_end_asset" {
  bucket = var.environment == "prod" ? "customer-front-end-asset-${data.aws_caller_identity.current.account_id}" : "${var.environment}-customer-front-end-asset-${data.aws_caller_identity.current.account_id}"

  tags = {
    Environment = var.environment
  }
}

resource "aws_s3_bucket_public_access_block" "customer_front_end_asset" {
  bucket = aws_s3_bucket.customer_front_end_asset.id

  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

# Only the public CloudFront distribution's OAC is allowed to read this
# bucket - scoped via AWS:SourceArn to that one distribution's ARN, not to
# every distribution in the account. Public access is fully blocked above,
# so this policy is the only way anything can ever read these objects.
resource "aws_s3_bucket_policy" "customer_front_end_asset" {
  bucket = aws_s3_bucket.customer_front_end_asset.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid       = "AllowPublicCloudFrontReadOnly"
        Effect    = "Allow"
        Principal = { Service = "cloudfront.amazonaws.com" }
        Action    = "s3:GetObject"
        Resource  = "${aws_s3_bucket.customer_front_end_asset.arn}/*"
        Condition = {
          StringEquals = {
            "AWS:SourceArn" = "${var.cloudfront_distribution_arn}"
          }
        }
      }
    ]
  })
}
