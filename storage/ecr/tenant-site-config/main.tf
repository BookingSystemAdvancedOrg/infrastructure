resource "aws_ecr_repository" "tenant_site_config" {
  name                 = var.environment == "prod" ? "tenant-site-config" : "${var.environment}-tenant-site-config"
  image_tag_mutability = "MUTABLE"

  image_scanning_configuration {
    scan_on_push = true
  }
}
