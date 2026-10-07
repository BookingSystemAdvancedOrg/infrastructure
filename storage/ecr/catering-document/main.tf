resource "aws_ecr_repository" "catering_document" {
  name                 = var.environment == "prod" ? "catering-document" : "${var.environment}-catering-document"
  image_tag_mutability = "MUTABLE"

  image_scanning_configuration {
    scan_on_push = true
  }
}
