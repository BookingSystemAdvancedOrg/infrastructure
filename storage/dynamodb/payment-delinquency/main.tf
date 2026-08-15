
resource "aws_dynamodb_table" "payment_delinquency" {
  name         = var.environment == "prod" ? "payment-delinquency" : "${var.environment}-payment-delinquency"
  billing_mode = "PAY_PER_REQUEST"
  hash_key     = "PK"
  range_key    = "SK"

  # PK: PHONE#<normalizedPhoneNumber> - one partition per customer, keyed
  # by phone since that's the identifier required at every booking. Lets
  # CreatePendingReservationFn check "does this phone number have any
  # unpaid debt" with a direct Query, no GSI needed.
  attribute {
    name = "PK"
    type = "S"
  }

  # SK: DEBT#<reservationId>. One record per failed charge - a phone
  # number can accumulate more than one over time (paid or not), so this
  # isn't a single flag per customer, it's a history of debts. Exact
  # PK + SK match is also what the stripe-webhook Lambda uses to update
  # one specific record directly once the Stripe Payment Link is paid.
  attribute {
    name = "SK"
    type = "S"
  }

  # No ttl here on purpose - unlike slot occupancy or reservations, these
  # records are the enforcement mechanism for blocking future bookings and
  # shouldn't silently expire while still unpaid. Add a retention policy
  # deliberately later if old, paid-off records need cleaning up.

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
