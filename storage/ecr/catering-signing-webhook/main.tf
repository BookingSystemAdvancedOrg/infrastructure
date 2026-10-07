resource "aws_ecr_repository" "catering_signing_webhook" {
  name                 = var.environment == "prod" ? "catering-signing-webhook" : "${var.environment}-catering-signing-webhook"
  image_tag_mutability = "MUTABLE"

  image_scanning_configuration {
    scan_on_push = true
  }
}
