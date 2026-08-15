
resource "aws_dynamodb_table" "slot_occupancy" {
  name         = var.environment == "prod" ? "slot-occupancy" : "${var.environment}-slot-occupancy"
  billing_mode = "PAY_PER_REQUEST"
  hash_key     = "PK"
  range_key    = "SK"

  # PK: LOCATION#<locationId> - one partition per restaurant.
  attribute {
    name = "PK"
    type = "S"
  }

  # SK: SLOT#<date>#<start-end>#<tableId>. Date comes right after "SLOT#"
  # on purpose: SK begins_with "SLOT#<date>" lists every occupied slot on
  # one day (or narrow further to "SLOT#<date>#<start-end>" for one time
  # range) with no separate index needed. An exact PK+SK match is also
  # what a reservation write checks against (attribute_not_exists) to
  # prevent double-booking a specific table/slot atomically.
  attribute {
    name = "SK"
    type = "S"
  }

  # Native DynamoDB expiry: once `ttl` (Unix epoch seconds) passes, AWS
  # automatically deletes the item in the background. This is a backstop,
  # not the primary cleanup path - cancellation should still explicitly
  # delete the row itself for immediate removal; ttl exists in case that
  # delete is ever missed, so nothing lingers forever. AWS typically clears
  # expired items within ~48 hours of expiry, not instantly.
  ttl {
    attribute_name = "ttl"
    enabled        = true
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
