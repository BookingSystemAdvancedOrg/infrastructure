resource "aws_ecr_repository" "webhook_payment_intent" {
  name                 = var.environment == "prod" ? "webhook-payment-intent" : "${var.environment}-webhook-payment-intent"
  image_tag_mutability = "MUTABLE"

  image_scanning_configuration {
    scan_on_push = true
  }
}
