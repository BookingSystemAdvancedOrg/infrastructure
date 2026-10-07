resource "aws_ecr_repository" "catering_offer" {
  name                 = var.environment == "prod" ? "catering-offer" : "${var.environment}-catering-offer"
  image_tag_mutability = "MUTABLE"

  image_scanning_configuration {
    scan_on_push = true
  }
}
