
resource "aws_dynamodb_table" "live_layout_element" {
  name         = var.environment == "prod" ? "live-layout-element" : "${var.environment}-live-layout-element"
  billing_mode = "PAY_PER_REQUEST"
  hash_key     = "PK"
  range_key    = "SK"

  # PK: LOCATION#<locationId> - one partition per restaurant's floor plan.
  # Loading the whole 3D scene for editing is just PK = LOCATION#<locationId> -
  # every wall, door, window, and table comes back in one query, no index
  # needed.
  attribute {
    name = "PK"
    type = "S"
  }

  # SK: LAYOUT#ELEMENT#<elementId> - one item per element, so a single
  # drag/resize/rotate during 3D editing is a cheap, isolated write to
  # exactly that element (PK + SK), not a rewrite of the whole layout.
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
