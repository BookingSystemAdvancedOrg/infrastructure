
# The restaurant's own catering menu, separate from the regular menu
# (MENU# items stay untouched). "Hämta från menyn" copies dishes in; there is
# no link back. Purged with the restaurant (tenant_purge_tables). No guest data.
resource "aws_dynamodb_table" "catering_menu" {
  name         = var.environment == "prod" ? "catering-menu" : "${var.environment}-catering-menu"
  billing_mode = "PAY_PER_REQUEST"
  hash_key     = "PK"
  range_key    = "SK"

  # PK: LOCATION#<locationId> - one Query returns a location's whole
  # catering menu (dishes and packages).
  attribute {
    name = "PK"
    type = "S"
  }

  # SK: DISH#<dishId> or PACKAGE#<packageId>.
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
  # wiping data. Dev stays off so the environment can still be torn down.
  deletion_protection_enabled = var.environment == "prod"

  tags = {
    Environment = var.environment
  }
}
