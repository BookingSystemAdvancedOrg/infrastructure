
resource "aws_dynamodb_table" "menu" {
  name         = var.environment == "prod" ? "menu" : "${var.environment}-menu"
  billing_mode = "PAY_PER_REQUEST"
  hash_key     = "PK"
  range_key    = "SK"

  # PK: LOCATION#<locationId> - one partition per restaurant's menu.
  # "Give me this location's full menu" is just PK = "LOCATION#<locationId>" -
  # no separate index needed, same reasoning as the user table.
  attribute {
    name = "PK"
    type = "S"
  }

  # SK: MENU#<menuItemId> - one dish per item within that location's menu.
  # PK + SK together let staff/owner get, update, or delete one
  # specific dish directly by its key.
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

  # Prod: a plan that deletes or replaces this table fails instead of
  # wiping data (set false in an apply first if that is really intended).
  # Dev stays off so the environment can still be torn down.
  deletion_protection_enabled = var.environment == "prod"

  tags = {
    Environment = var.environment
  }
}
