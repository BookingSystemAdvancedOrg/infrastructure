resource "aws_ecr_repository" "pre_signed_url" {
  name                 = var.environment == "prod" ? "pre-signed-url" : "${var.environment}-pre-signed-url"
  image_tag_mutability = "MUTABLE"

  image_scanning_configuration {
    scan_on_push = true
  }
}
