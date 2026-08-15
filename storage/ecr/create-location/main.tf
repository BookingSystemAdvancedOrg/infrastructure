resource "aws_ecr_repository" "create_location" {
  name                 = var.environment == "prod" ? "create-location" : "${var.environment}-create-location"
  image_tag_mutability = "MUTABLE"

  image_scanning_configuration {
    scan_on_push = true
  }
}
