resource "aws_ecr_repository" "cancel_reservation" {
  name                 = var.environment == "prod" ? "cancel-reservation" : "${var.environment}-cancel-reservation"
  image_tag_mutability = "MUTABLE"

  image_scanning_configuration {
    scan_on_push = true
  }
}
