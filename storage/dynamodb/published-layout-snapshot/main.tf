
resource "aws_dynamodb_table" "published_layout_snapshot" {
  name         = var.environment == "prod" ? "published-layout-snapshot" : "${var.environment}-published-layout-snapshot"
  billing_mode = "PAY_PER_REQUEST"
  hash_key     = "PK"
  range_key    = "SK"

  # PK: LOCATION#<locationId> - one partition per restaurant's full
  # version history.
  attribute {
    name = "PK"
    type = "S"
  }

  # SK: LAYOUT#v<N>. PK + SK together let staff get/update one specific
  # version directly (reactivate, edit) once they know which version.
  #
  # Listing every version for a location is PK = LOCATION#<locationId> +
  # SK begins_with "LAYOUT#" - no index needed, since SCD Type 2 keeps a
  # small, bounded number of versions per location, not an ever-growing log.
  #
  # "Find the current, still-bookable layout" is done the same way: query
  # by PK, then check each version's isCurrent/expiresAt fields in app
  # code. That's a filter-after-read, same reasoning as the menu table's
  # active flag - fine at this scale since one location only ever has a
  # handful of layout versions to look through, not thousands.
  #
  # Deliberately no attribute/GSI on isCurrent or expiresAt: the useful
  # unit here is "one location's whole version history", which the
  # primary key already returns in a single query.
  attribute {
    name = "SK"
    type = "S"
  }

  # No `ttl` block here on purpose - unlike slot occupancy, these rows are
  # never meant to auto-delete. `expiresAt` is a plain data field your app
  # compares to "now" to decide whether a version is still bookable; SCD
  # Type 2 requires every version to stick around permanently for history.

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
