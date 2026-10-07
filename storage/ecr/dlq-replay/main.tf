resource "aws_ecr_repository" "dlq_replay" {
  name                 = var.environment == "prod" ? "dlq-replay" : "${var.environment}-dlq-replay"
  image_tag_mutability = "MUTABLE"

  image_scanning_configuration {
    scan_on_push = true
  }
}
