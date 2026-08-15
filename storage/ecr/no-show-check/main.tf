resource "aws_ecr_repository" "no_show_check" {
  name                 = var.environment == "prod" ? "no-show-check" : "${var.environment}-no-show-check"
  image_tag_mutability = "MUTABLE"

  image_scanning_configuration {
    scan_on_push = true
  }
}
