resource "aws_ecr_repository" "activate_layout_version" {
  name                 = var.environment == "prod" ? "activate-layout-version" : "${var.environment}-activate-layout-version"
  image_tag_mutability = "MUTABLE"

  image_scanning_configuration {
    scan_on_push = true
  }
}