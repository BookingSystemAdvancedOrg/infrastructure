
resource "aws_dynamodb_table" "catering_requests" {
  name         = var.environment == "prod" ? "catering-requests" : "${var.environment}-catering-requests"
  billing_mode = "PAY_PER_REQUEST"
  hash_key     = "PK"
  range_key    = "SK"

  # PK: LOCATION#<locationId> - keeps all requests for one restaurant in
  # a single partition, so staff can query everything for their location
  # in one read.
  attribute {
    name = "PK"
    type = "S"
  }

  # SK: REQUEST#<requestId> (UUID) - unique per submission. Combined with
  # PK this gives a direct GetItem for a single request and a Query for the
  # full list. Filtering by status (pending/accepted/rejected) happens in
  # app code; the set per location is small enough that a filter-after-read
  # is fine, and adding a status GSI would just increase write cost and
  # complexity for minimal gain at this scale.
  attribute {
    name = "SK"
    type = "S"
  }

  # No TTL - catering requests are business records that should be kept
  # for the full retention period; archiving is handled at the application
  # layer if needed.

  point_in_time_recovery {
    enabled = true
  }

  server_side_encryption {
    enabled = true
  }

  # NEW_IMAGE only - the owner notification below fires on INSERT (a brand
  # new request), never on a status transition, so there's no OldImage to
  # compare against. If a MODIFY-triggered notification (e.g. "request
  # accepted") is ever added here, switch this to NEW_AND_OLD_IMAGES then,
  # same as the reservation/order tables do for their transition filters.
  stream_enabled   = true
  stream_view_type = "NEW_IMAGE"

  tags = {
    Environment = var.environment
  }
}

# Invokes NotificationFn on every new catering request (INSERT with
# status "pending") so the restaurant owner gets a link-only email - no
# offer details in the body, by design (see docs/catering ticket). Anchored
# to status = "pending" rather than any INSERT so a future bulk-import or
# migration script that writes catering-requests items directly doesn't
# accidentally spam an email per row.
#
# Filtering happens here, at the event source mapping, so NotificationFn is
# never even invoked for irrelevant stream records - same pattern as
# notify_on_reservation_status_change (storage/dynamodb/reservation) and
# notify_on_order_paid (storage/dynamodb/order).
resource "aws_lambda_event_source_mapping" "notify_on_catering_request_created" {
  event_source_arn  = aws_dynamodb_table.catering_requests.stream_arn
  function_name     = var.notification_lambda_arn # this can be NAME or ARN, but ARN is safer in case the Lambda is in a different account
  enabled           = true
  starting_position = "LATEST"
  batch_size        = 10

  filter_criteria {
    filter {
      pattern = jsonencode({
        eventName = ["INSERT"]
        dynamodb = {
          NewImage = {
            status = { S = ["pending"] }
          }
        }
      })
    }
  }
}
