
resource "aws_ecr_repository" "catering_settings" {
  name                 = var.environment == "prod" ? "catering-settings" : "${var.environment}-catering-settings"
  image_tag_mutability = "MUTABLE"

  image_scanning_configuration {
    scan_on_push = true
  }
}
