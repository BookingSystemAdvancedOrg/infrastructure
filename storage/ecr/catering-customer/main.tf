resource "aws_ecr_repository" "catering_customer" {
  name                 = var.environment == "prod" ? "catering-customer" : "${var.environment}-catering-customer"
  image_tag_mutability = "MUTABLE"

  image_scanning_configuration {
    scan_on_push = true
  }
}
