resource "aws_ecr_repository" "manage_user" {
  name                 = var.environment == "prod" ? "manage-user" : "${var.environment}-manage-user"
  image_tag_mutability = "MUTABLE"

  image_scanning_configuration {
    scan_on_push = true
  }
}
