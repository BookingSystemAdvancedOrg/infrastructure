# Attempt counters for public writes (online bookings): one row per client
# (hashed IP address, phone number or e-mail) and time window, counted up
# with a conditional UpdateItem until the window's limit
# (application shared/request_guard.py). Rows only matter while their
# window lasts; TTL removes them afterwards.
resource "aws_dynamodb_table" "request_guard" {
  name         = var.environment == "prod" ? "request-guard" : "${var.environment}-request-guard"
  billing_mode = "PAY_PER_REQUEST"
  hash_key     = "PK"

  # PK: <kind>#<sha256 of the identifier>#<window seconds>#<window number>
  attribute {
    name = "PK"
    type = "S"
  }

  ttl {
    attribute_name = "ttl"
    enabled        = true
  }

  # Short-lived counters: nothing worth restoring. Point-in-time recovery
  # would only add cost.
  point_in_time_recovery {
    enabled = false
  }

  server_side_encryption {
    enabled = true
  }

  tags = {
    Environment = var.environment
  }
}
