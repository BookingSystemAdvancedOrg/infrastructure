
resource "aws_ecr_repository" "catering_requests" {
  name                 = var.environment == "prod" ? "catering-requests" : "${var.environment}-catering-requests"
  image_tag_mutability = "MUTABLE"

  image_scanning_configuration {
    scan_on_push = true
  }
}
