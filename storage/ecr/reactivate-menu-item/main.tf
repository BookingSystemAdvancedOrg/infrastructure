resource "aws_ecr_repository" "reactivate_menu_item" {
  name                 = var.environment == "prod" ? "reactivate-menu-item" : "${var.environment}-reactivate-menu-item"
  image_tag_mutability = "MUTABLE"

  image_scanning_configuration {
    scan_on_push = true
  }
}
