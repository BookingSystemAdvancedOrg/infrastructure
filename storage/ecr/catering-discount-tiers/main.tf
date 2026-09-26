
resource "aws_ecr_repository" "catering_discount_tiers" {
  name                 = var.environment == "prod" ? "catering-discount-tiers" : "${var.environment}-catering-discount-tiers"
  image_tag_mutability = "MUTABLE"

  image_scanning_configuration {
    scan_on_push = true
  }
}
