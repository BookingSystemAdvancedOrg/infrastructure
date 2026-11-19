# The table-order table: tabs staff open at the table (Bordsbeställning).
# Booqy takes no payment here; the guest pays in the restaurant's own
# system and staff close the tab ("betald i kassan"). Kept apart from the
# order table on purpose: no stream, so accounting, Statistik,
# finance-rollup, CRM, marketing, notification and data-retention never
# see a tab. One partition per location (application shared/table_orders.py).
#
# Item types (PK | SK):
#
#   LOCATION#<l> | TAB#<openedDate>#<tabId>  the tab (items, rounds, history)
#   LOCATION#<l> | TID#<tabId>               pointer {date}: load a tab by id
#   LOCATION#<l> | OPEN#<tableId>            lock, one open tab per table
#   LOCATION#<l> | REQ#<requestId>           idempotency of one mutation
#   LOCATION#<l> | STATE                     {version}: cheap poll for changes
#
# Everything expires by ttl: closed tabs 14 days after close (guest names),
# open tabs and locks after 48 h without a write, request rows after 24 h.
# tenant-purge does not touch this table; the ttl clears it within 14 days.

resource "aws_dynamodb_table" "table_order" {
  name         = var.environment == "prod" ? "table-order" : "${var.environment}-table-order"
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

  deletion_protection_enabled = var.environment == "prod"

  tags = {
    Environment = var.environment
  }
}
