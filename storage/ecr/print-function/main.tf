# ECR repository for one of the kitchen printing Lambdas (print-jobs,
# print-device). Same settings as every other function's
# repository; one module instance per function in config.tf (module
# "<fn>_ecr"), which is what CI's bootstrap step looks for.
locals {
  name = var.environment == "prod" ? var.function : "${var.environment}-${var.function}"
}

resource "aws_ecr_repository" "this" {
  name                 = local.name
  image_tag_mutability = "MUTABLE"

  image_scanning_configuration {
    scan_on_push = true
  }
}

# Every deploy pushes a new image; the 30 most recent stay for rollbacks.
resource "aws_ecr_lifecycle_policy" "this" {
  repository = aws_ecr_repository.this.name

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
