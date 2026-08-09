resource "aws_ecr_repository" "publish_layout" {
  name                 = var.environment == "prod" ? "publish-layout" : "${var.environment}-publish-layout"
  image_tag_mutability = "MUTABLE"

  image_scanning_configuration {
    scan_on_push = true
  }
}
