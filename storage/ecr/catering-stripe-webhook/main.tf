resource "aws_ecr_repository" "catering_stripe_webhook" {
  name                 = var.environment == "prod" ? "catering-stripe-webhook" : "${var.environment}-catering-stripe-webhook"
  image_tag_mutability = "MUTABLE"

  image_scanning_configuration {
    scan_on_push = true
  }
}
