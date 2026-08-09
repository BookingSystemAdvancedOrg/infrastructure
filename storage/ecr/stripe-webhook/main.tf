resource "aws_ecr_repository" "stripe_webhook" {
  name                 = var.environment == "prod" ? "stripe-webhook" : "${var.environment}-stripe-webhook"
  image_tag_mutability = "MUTABLE"

  image_scanning_configuration {
    scan_on_push = true
  }
}
