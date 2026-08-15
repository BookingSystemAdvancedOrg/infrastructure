resource "aws_ecr_repository" "block_table" {
  name                 = var.environment == "prod" ? "block-table" : "${var.environment}-block-table"
  image_tag_mutability = "MUTABLE"

  image_scanning_configuration {
    scan_on_push = true
  }
}
