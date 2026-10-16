resource "aws_ecr_repository" "manage_layout_element" {
  name                 = var.environment == "prod" ? "manage-layout-element" : "${var.environment}-manage-layout-element"
  image_tag_mutability = "MUTABLE"

  image_scanning_configuration {
    scan_on_push = true
  }
}

# Every deploy pushes a new image; without this the repository grows (and
# is billed) forever. The 30 most recent stay, enough for any rollback.
resource "aws_ecr_lifecycle_policy" "manage_layout_element" {
  repository = aws_ecr_repository.manage_layout_element.name

  policy = jsonencode({
    rules = [
      {
        rulePriority = 1
        description  = "Keep the 30 most recent images"
        selection = {
          tagStatus   = "any"
          countType   = "imageCountMoreThan"
          countNumber = 30
        }
        action = { type = "expire" }
      }
    ]
  })
}
