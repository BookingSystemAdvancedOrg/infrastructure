resource "aws_ecr_repository" "manage_menu" {
  name                 = var.environment == "prod" ? "manage-menu" : "${var.environment}-manage-menu"
  image_tag_mutability = "MUTABLE"

  image_scanning_configuration {
    scan_on_push = true
  }
}
