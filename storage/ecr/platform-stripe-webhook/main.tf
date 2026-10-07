resource "aws_ecr_repository" "platform_stripe_webhook" {
  name                 = var.environment == "prod" ? "platform-stripe-webhook" : "${var.environment}-platform-stripe-webhook"
  image_tag_mutability = "MUTABLE"

  image_scanning_configuration {
    scan_on_push = true
  }
}
