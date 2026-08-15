resource "aws_ecr_repository" "get_location" {
  name                 = var.environment == "prod" ? "get-location" : "${var.environment}-get-location"
  image_tag_mutability = "MUTABLE"

  image_scanning_configuration {
    scan_on_push = true
  }
}
