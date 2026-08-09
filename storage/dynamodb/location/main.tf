
resource "aws_dynamodb_table" "location" {
  name         = var.environment == "prod" ? "location" : "${var.environment}-location"
  billing_mode = "PAY_PER_REQUEST"
  hash_key     = "PK"
  range_key    = "SK"

  # PK: always "PLATFORM" - every location lives in this one partition, so
  # PK = "PLATFORM" alone lists every restaurant on the platform (e.g. a
  # location picker, or super-admin's onboarding list). Same pattern as
  # owner_user/super_admin rows on the user table.
  attribute {
    name = "PK"
    type = "S"
  }

  # SK: LOCATION#<locationId>. PK + SK together get one specific location's
  # record (including its booking policy) directly.
  attribute {
    name = "SK"
    type = "S"
  }

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
