resource "aws_ecr_repository" "get_order" {
  name                 = var.environment == "prod" ? "get-order" : "${var.environment}-get-order"
  image_tag_mutability = "MUTABLE"

  image_scanning_configuration {
    scan_on_push = true
  }
}
