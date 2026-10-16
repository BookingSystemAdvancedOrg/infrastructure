
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

  # NEW_AND_OLD_IMAGES (not just NEW_IMAGE) is required here - the
  # notification function compares OldImage.notice.id with NewImage's so a
  # notice is sent once. Same reasoning as the reservation table.
  stream_enabled   = true
  stream_view_type = "NEW_AND_OLD_IMAGES"

  # Prod: a plan that deletes or replaces this table fails instead of
  # wiping data (set false in an apply first if that is really intended).
  # Dev stays off so the environment can still be torn down.
  deletion_protection_enabled = var.environment == "prod"

  tags = {
    Environment = var.environment
  }
}

# Invokes NotificationFn for order records that carry a guest notice
# (shared/orders.py): order_confirmed (payment confirmed - SMS + receipt),
# order_ready (pickup ready - SMS), order_cancelled (refunded - SMS +
# e-mail). Same contract as the reservation table: a write that should
# reach the guest sets notice = {id, type, at}; the function sends only when
# the id is new (OldImage.notice.id differs), so later writes to the order
# (kitchen moves, refund bookkeeping) never resend anything.
#
# Filtering happens here, at the event source mapping, so NotificationFn is
# never even invoked for irrelevant stream records (pending orders, the
# daily number counter, pointers).
resource "aws_lambda_event_source_mapping" "notify_on_order_paid" {
  event_source_arn  = aws_dynamodb_table.order.stream_arn
  function_name     = var.notification_lambda_arn # NAME or ARN both work, but ARN is safer in case the Lambda is in a different account
  enabled           = true
  starting_position = "LATEST"
  batch_size        = 10
  # Up to 10 batches per stream shard at once (records with the same key
  # stay in order): a dinner-rush burst of notices is sent in parallel
  # instead of queueing behind one batch at a time.
  parallelization_factor = 10

  # A failing batch must not block this shard for the stream's full 24h:
  # cap retries, bisect to isolate a poison record, then hand the batch to
  # the notification-stream DLQ, which dlq-replay drains on a schedule.
  maximum_retry_attempts         = 5
  bisect_batch_on_function_error = true

  destination_config {
    on_failure {
      destination_arn = var.notification_dlq_arn
    }
  }

  filter_criteria {
    filter {
      pattern = jsonencode({
        eventName = ["INSERT", "MODIFY"]
        dynamodb = {
          NewImage = {
            notice = { M = { id = { S = [{ exists = true }] } } }
          }
        }
      })
    }
  }
}
