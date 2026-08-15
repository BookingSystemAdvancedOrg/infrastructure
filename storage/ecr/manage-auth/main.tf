resource "aws_ecr_repository" "manage_auth" {
  name                 = var.environment == "prod" ? "manage-auth" : "${var.environment}-manage-auth"
  image_tag_mutability = "MUTABLE"

  image_scanning_configuration {
    scan_on_push = true
  }
}
