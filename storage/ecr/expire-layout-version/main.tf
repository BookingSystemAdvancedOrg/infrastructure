resource "aws_ecr_repository" "expire_layout_version" {
  name                 = var.environment == "prod" ? "expire-layout-version" : "${var.environment}-expire-layout-version"
  image_tag_mutability = "MUTABLE"

  image_scanning_configuration {
    scan_on_push = true
  }
}
