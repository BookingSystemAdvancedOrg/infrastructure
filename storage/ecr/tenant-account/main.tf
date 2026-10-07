resource "aws_ecr_repository" "tenant_account" {
  name                 = var.environment == "prod" ? "tenant-account" : "${var.environment}-tenant-account"
  image_tag_mutability = "MUTABLE"

  image_scanning_configuration {
    scan_on_push = true
  }
}
