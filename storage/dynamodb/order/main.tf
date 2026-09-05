
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

  # Native DynamoDB expiry on `ttl` (Unix epoch seconds) - a BACKSTOP, not
  # the primary cleanup. The contract with the application code:
  #
  #   - create-order sets ttl = now + ~2x the Checkout session expiry
  #     (session expires_at 30 min -> ttl ~60 min) on the new
  #     pending/processing item.
  #   - the webhook REMOVEs the ttl attribute on ANY resolution
  #     (processing -> paid or -> failed), so resolved orders - the actual
  #     financial records - are never expired.
  #
  # In the normal world checkout.session.expired resolves an abandoned
  # order to "failed" at ~30 min and clears the ttl; this only ever fires
  # when that webhook never arrived (lost event, endpoint outage, handler
  # bug), guaranteeing no immortal "processing" ghost. TTL deletion is
  # lazy (minutes-to-hours after expiry, no exact timing) - user-visible
  # 30-minute behavior belongs to the expired webhook, never to this.
  # The margin above session expiry exists so a slow async payment result
  # or a retried webhook always finds the item still present; handlers
  # must still guard updates with attribute_exists(PK) so a late webhook
  # can never resurrect a TTL-deleted order as a partial item.
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

  # NEW_AND_OLD_IMAGES (not just NEW_IMAGE) is required here - the filters
  # below compare OldImage.paymentStatus against NewImage.paymentStatus to
  # catch only the transition out of "processing", not every write already
  # sitting in a paid/failed state. Same reasoning as the reservation table.
  stream_enabled   = true
  stream_view_type = "NEW_AND_OLD_IMAGES"

  tags = {
    Environment = var.environment
  }
}

# Invokes NotificationFn on exactly one transition: processing -> paid.
# This is the receipt/"we've got your order" message.
#
# The filter anchors OldImage to exactly "processing" on purpose: kitchen
# writes to an already-paid order (status -> preparing/served, updatedAt
# bumps) change paymentStatus not at all or not from "processing", so they
# can never re-fire the receipt. Transitions out of "paid" (refunds) don't
# match either.
#
# Deliberately NOT here: processing -> failed. Today the success page is
# expected to surface a failed payment to the customer. Note the gap that
# leaves once Swish/Klarna are live: their payments can fail AFTER the
# customer has left the browser (async_payment_failed), and no page exists
# to show it on - if that becomes a support-call source, the fix is a
# second filter block here (OldImage processing -> NewImage failed), OR'd
# with this one.
#
# Filtering happens here, at the event source mapping, so NotificationFn is
# never even invoked for irrelevant stream records.
resource "aws_lambda_event_source_mapping" "notify_on_order_paid" {
  event_source_arn  = aws_dynamodb_table.order.stream_arn
  function_name     = var.notification_lambda_arn # NAME or ARN both work, but ARN is safer in case the Lambda is in a different account
  enabled           = true
  starting_position = "LATEST"
  batch_size        = 10

  filter_criteria {
    filter {
      pattern = jsonencode({
        eventName = ["MODIFY"]
        dynamodb = {
          OldImage = {
            paymentStatus = { S = ["processing"] }
          }
          NewImage = {
            paymentStatus = { S = ["paid"] }
          }
        }
      })
    }
  }
}
