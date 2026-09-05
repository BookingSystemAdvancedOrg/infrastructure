
resource "aws_dynamodb_table" "order" {
  name         = var.environment == "prod" ? "order" : "${var.environment}-order"
  billing_mode = "PAY_PER_REQUEST"
  hash_key     = "PK"
  range_key    = "SK"

  # PK: LOCATION#<locationId> - one partition per restaurant's food orders,
  # same shape as the menu and reservation tables. Ordering is deliberately
  # decoupled from reservations: an order exists whether the customer booked
  # a table, walked in, or ordered via QR at the table. "Give me this
  # location's orders" is a single Query on the partition with no GSI.
  attribute {
    name = "PK"
    type = "S"
  }

  # SK: ORDER#<date>#<orderId>. Date comes right after "ORDER#" on
  # purpose, same as the reservation table: SK begins_with "ORDER#<date>"
  # gives the kitchen/staff dashboard a day's orders with no separate
  # index. That same one-day Query backs the admin/staff arrivals view -
  # who ordered what and when: each item carries customerName (plus
  # customerId/reservationId when known), and matching an arriving guest
  # to their pre-order is a client-side filter over that day's orders,
  # not a GSI. Exact PK + SK gets one specific order directly for status
  # updates (confirmed, preparing, served, etc.). Stripe webhooks don't
  # need a lookup path here at all - the payment-intent Lambda puts
  # locationId/orderId/date into the PaymentIntent's metadata at creation,
  # so the webhook reconstructs the exact key from the event. If "look up
  # an order by ID alone" ever becomes a real access pattern beyond that,
  # it's a GSI on orderId added later, not a reason to re-key this table.
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
