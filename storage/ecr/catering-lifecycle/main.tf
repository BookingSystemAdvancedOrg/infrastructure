resource "aws_ecr_repository" "catering_lifecycle" {
  name                 = var.environment == "prod" ? "catering-lifecycle" : "${var.environment}-catering-lifecycle"
  image_tag_mutability = "MUTABLE"

  image_scanning_configuration {
    scan_on_push = true
  }
}
