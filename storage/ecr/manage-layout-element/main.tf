resource "aws_ecr_repository" "manage_layout_element" {
  name                 = var.environment == "prod" ? "manage-layout-element" : "${var.environment}-manage-layout-element"
  image_tag_mutability = "MUTABLE"

  image_scanning_configuration {
    scan_on_push = true
  }
}
