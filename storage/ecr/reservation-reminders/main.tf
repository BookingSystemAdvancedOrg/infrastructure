resource "aws_ecr_repository" "reservation_reminders" {
  name                 = var.environment == "prod" ? "reservation-reminders" : "${var.environment}-reservation-reminders"
  image_tag_mutability = "MUTABLE"

  image_scanning_configuration {
    scan_on_push = true
  }
}
