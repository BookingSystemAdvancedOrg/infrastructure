resource "aws_ecr_repository" "get_reservation" {
  name                 = var.environment == "prod" ? "get-reservation" : "${var.environment}-get-reservation"
  image_tag_mutability = "MUTABLE"

  image_scanning_configuration {
    scan_on_push = true
  }
}
