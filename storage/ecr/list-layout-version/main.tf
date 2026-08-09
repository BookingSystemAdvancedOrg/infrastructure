resource "aws_ecr_repository" "list_layout_version" {
  name                 = var.environment == "prod" ? "list-layout-version" : "${var.environment}-list-layout-version"
  image_tag_mutability = "MUTABLE"

  image_scanning_configuration {
    scan_on_push = true
  }
}
