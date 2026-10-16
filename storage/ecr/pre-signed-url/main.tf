resource "aws_ecr_repository" "pre_signed_url" {
  name                 = var.environment == "prod" ? "pre-signed-url" : "${var.environment}-pre-signed-url"
  image_tag_mutability = "MUTABLE"

  image_scanning_configuration {
    scan_on_push = true
  }
}

# Every deploy pushes a new image; without this the repository grows (and
# is billed) forever. The 30 most recent stay, enough for any rollback.
resource "aws_ecr_lifecycle_policy" "pre_signed_url" {
  repository = aws_ecr_repository.pre_signed_url.name

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
