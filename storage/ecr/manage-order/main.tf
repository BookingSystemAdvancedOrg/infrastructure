resource "aws_ecr_repository" "manage_order" {
  name                 = var.environment == "prod" ? "manage-order" : "${var.environment}-manage-order"
  image_tag_mutability = "MUTABLE"

  image_scanning_configuration {
    scan_on_push = true
  }
}
