resource "aws_ecr_repository" "platform_tenants" {
  name                 = var.environment == "prod" ? "platform-tenants" : "${var.environment}-platform-tenants"
  image_tag_mutability = "MUTABLE"

  image_scanning_configuration {
    scan_on_push = true
  }
}

# The sbs-admin pipeline pushes an image per commit (tagged with the commit
# SHA + latest). Keep the last 30 so a rollback is a one-line
# update-function-code, without paying for every image forever.
resource "aws_ecr_lifecycle_policy" "platform_tenants" {
  repository = aws_ecr_repository.platform_tenants.name

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
