resource "aws_ecr_repository" "mark_arrived" {
  name                 = var.environment == "prod" ? "mark-arrived" : "${var.environment}-mark-arrived"
  image_tag_mutability = "MUTABLE"

  image_scanning_configuration {
    scan_on_push = true
  }
}
