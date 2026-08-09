
resource "aws_dynamodb_table" "user" {
  name         = var.environment == "prod" ? "user" : "${var.environment}-user"
  billing_mode = "PAY_PER_REQUEST"
  hash_key     = "PK"
  range_key    = "SK"

  # PK: USER#<cognitoSub>. Keyed by sub rather than location - the frequent
  # operation is "look up the calling user's role/location from their
  # token" (used by BlockTableFn and anything else doing per-request
  # authorization), which this makes a direct GetItem, no Query, no GSI.
  attribute {
    name = "PK"
    type = "S"
  }

  # SK: fixed constant "PROFILE" - PK already uniquely identifies the user
  # (one item per sub), so SK doesn't need to distinguish anything. It
  # exists only so this table follows the same PK+SK composite-key shape
  # as the rest of the tables in this project.
  #
  # Listing every staff member at a given location is the rare operation
  # here, and isn't served by the primary key - it's handled with an
  # occasional Scan filtered on locationId, which is cheap enough given
  # this table's realistic size (a staff directory, not millions of rows).
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
