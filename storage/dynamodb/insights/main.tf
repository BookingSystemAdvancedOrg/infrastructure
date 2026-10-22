# The insights table: a restaurant's own figures per location and day, the
# data behind Statistik in the admin app. No personal data: counts, sums and
# histograms only (no names, phone numbers or emails).
#
# Separate from the finance table on purpose: finance holds the operator's
# figures (AWS cost, MRR, SMS revenue) that must never reach a restaurant,
# and the restaurant-facing insights Lambda gets no access to it.
#
# Keyed like the operational tables (LOCATION#<locationId>), so tenant-purge
# deletes it with the rest of an offboarded restaurant's location data, and a
# read never needs more than the tenant's own locations (shared/tenant.py).
#
# Item types (PK | SK):
#
#   LOCATION#<locationId> | DAY#<yyyy-mm-dd>   the day: bookings per hour and
#                                               source, table minutes booked
#                                               and open, orders per hour,
#                                               dishes, catering, website
#                                               visits (shared/insights.py)
#   LOCATION#<locationId> | JOB#latest          the last rollup of that location
#
# Written by insights-rollup (nightly, recomputes the last days). Read by
# insights (GET /insights). A year at one location is one Query.

locals {
  table_name = var.environment == "prod" ? "insights" : "${var.environment}-insights"
}

resource "aws_dynamodb_table" "insights" {
  name         = local.table_name
  billing_mode = "PAY_PER_REQUEST"
  hash_key     = "PK"
  range_key    = "SK"

  attribute {
    name = "PK"
    type = "S"
  }

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
