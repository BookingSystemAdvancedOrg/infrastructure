
resource "aws_dynamodb_table" "catering_discount_tiers" {
  name         = var.environment == "prod" ? "catering-discount-tiers" : "${var.environment}-catering-discount-tiers"
  billing_mode = "PAY_PER_REQUEST"
  hash_key     = "PK"
  range_key    = "SK"

  # PK: LOCATION#<locationId> - one partition per restaurant so a single
  # Query returns every tier configured for that location.
  attribute {
    name = "PK"
    type = "S"
  }

  # SK: TIER#<tierId> (UUID) - lets the owner address individual tiers
  # for updates and deletes without needing a GSI.  The application sorts
  # tiers by fromPortions after reading them back; keeping the sort in
  # app-code avoids index overhead for what will always be a tiny set
  # (< 10 tiers per location in practice).
  attribute {
    name = "SK"
    type = "S"
  }

  # No TTL - tiers persist until the owner explicitly removes them.

  point_in_time_recovery {
    enabled = true
  }

  server_side_encryption {
    enabled = true
  }

  tags = {
    Environment = var.environment
  }
}
