
resource "aws_dynamodb_table" "order" {
  name         = var.environment == "prod" ? "order" : "${var.environment}-order"
  billing_mode = "PAY_PER_REQUEST"
  hash_key     = "PK"
  range_key    = "SK"

  # PK: RESERVATION#<reservationId> - one partition per table visit, same
  # shape as the reservation table's own PK. Lets a single Query pull
  # every order placed during that visit (e.g. rendering a table's tab)
  # with no GSI.
  attribute {
    name = "PK"
    type = "S"
  }

  # SK: ORDER#<orderId>. Exact PK + SK gets one specific order directly
  # for status updates. If "look up an order by ID alone" turns out to be
  # a real access pattern (not just "within a known reservation"), that's
  # a GSI on orderId added later, not a reason to key this table by
  # orderId alone up front.
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
