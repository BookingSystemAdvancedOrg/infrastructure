resource "aws_ecr_repository" "payment_intent" {
  name                 = var.environment == "prod" ? "payment-intent" : "${var.environment}-payment-intent"
  image_tag_mutability = "MUTABLE"

  image_scanning_configuration {
    scan_on_push = true
  }
}
