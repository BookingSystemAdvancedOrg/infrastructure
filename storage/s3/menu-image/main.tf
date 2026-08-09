
# S3 bucket names are globally unique across every AWS account, not just
# this one - the account ID suffix guarantees no collision without needing
# a manually-chosen unique name per fork/customer.
data "aws_caller_identity" "current" {}

resource "aws_s3_bucket" "menu_image" {
  bucket = var.environment == "prod" ? "menu-image-${data.aws_caller_identity.current.account_id}" : "${var.environment}-menu-image-${data.aws_caller_identity.current.account_id}"

  tags = {
    Environment = var.environment
  }
}

resource "aws_s3_bucket_public_access_block" "menu_image" {
  bucket = aws_s3_bucket.menu_image.id

  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

# Both CloudFront distributions read from this one bucket - the public site
# shows menu images to customers, the admin site shows them while staff
# edit the menu - so both distributions' ARNs are allowed here, unlike
# customer/admin-front-end-asset which are each scoped to just one.
resource "aws_s3_bucket_policy" "menu_image" {
  bucket = aws_s3_bucket.menu_image.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid       = "AllowBothCloudFrontDistributionsReadOnly"
        Effect    = "Allow"
        Principal = { Service = "cloudfront.amazonaws.com" }
        Action    = "s3:GetObject"
        Resource  = "${aws_s3_bucket.menu_image.arn}/*"
        Condition = {
          StringEquals = {
            "AWS:SourceArn" = [
              "${var.public_cloudfront_distribution_arn}",
              "${var.private_cloudfront_distribution_arn}",
            ]
          }
        }
      }
    ]
  })
}

