# The finance table: what every customer costs and pays, one row per day.
# Separate from the tenant table on purpose - tenant-purge deletes a
# restaurant's TENANT#<id> partitions in that table and the Finance page
# must still show what an offboarded or purged customer paid and cost - and
# so that the roles that write counters (notification, marketing-send) get
# no access to customer profiles.
#
# Item types (PK | SK):
#
#   TENANT#<tenantId>  | DAY#<yyyy-mm-dd>        usage that day (requests, bookings,
#                                                 orders, emails, sms, marketingEmails),
#                                                 allocated AWS cost (costSek + the
#                                                 split per bucket), revenue booked that
#                                                 day (invoicedSek, paidSek, creditedSek,
#                                                 ex VAT), mrrSek snapshot, planId, active
#   TENANT#<tenantId>  | INVOICE#<yyyy-mm-dd>#<in_...>  one Stripe invoice: number, status,
#                                                 amounts, due/paid dates, links
#   PLATFORM           | COST#<yyyy-mm-dd>        the account's cost that day from Cost
#                                                 Explorer: USD by service, the rate used
#   PLATFORM           | DAY#<yyyy-mm-dd>         platform totals that day (customers,
#                                                 MRR, cost, invoiced, paid, usage)
#   PLATFORM           | JOB#latest / JOB#<day>   the last finance-rollup run: when, what,
#                                                 warnings (e.g. Cost Explorer not enabled)
#
# Written by finance-rollup (nightly), platform-stripe-webhook (/billing
# events), notification and marketing-send (counters, ADD) and
# platform-tenants (Stripe import, rebuild). Read by platform-tenants
# (Finance page). Every sum over a date range is a Query on one partition.

locals {
  table_name = var.environment == "prod" ? "finance" : "${var.environment}-finance"
}

resource "aws_dynamodb_table" "finance" {
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

  # Bookkeeping figures: never dropped by a careless apply in production.
  deletion_protection_enabled = var.environment == "prod"

  tags = {
    Environment = var.environment
  }
}
