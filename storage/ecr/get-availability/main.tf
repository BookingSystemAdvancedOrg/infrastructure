resource "aws_ecr_repository" "get_availability" {
  name                 = var.environment == "prod" ? "get-availability" : "${var.environment}-get-availability"
  image_tag_mutability = "MUTABLE"

  image_scanning_configuration {
    scan_on_push = true
  }
}
