resource "aws_ecr_repository" "create_pending_reservation" {
  name                 = var.environment == "prod" ? "create-pending-reservation" : "${var.environment}-create-pending-reservation"
  image_tag_mutability = "MUTABLE"

  image_scanning_configuration {
    scan_on_push = true
  }
}
