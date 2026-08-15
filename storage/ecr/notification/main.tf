resource "aws_ecr_repository" "notification" {
  name                 = var.environment == "prod" ? "notification" : "${var.environment}-notification"
  image_tag_mutability = "MUTABLE"

  image_scanning_configuration {
    scan_on_push = true
  }
}
