resource "aws_ecr_repository" "get_menu" {
  name                 = var.environment == "prod" ? "get-menu" : "${var.environment}-get-menu"
  image_tag_mutability = "MUTABLE"

  image_scanning_configuration {
    scan_on_push = true
  }
}
