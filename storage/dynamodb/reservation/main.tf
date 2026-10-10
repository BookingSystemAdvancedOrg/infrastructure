
# Shared by the table itself and the stream/event-source-mapping resources
# below, so the naming convention only has to be written once.
locals {
  table_name = var.environment == "prod" ? "reservation" : "${var.environment}-reservation"
}

resource "aws_dynamodb_table" "reservation" {
  name         = local.table_name
  billing_mode = "PAY_PER_REQUEST"
  hash_key     = "PK"
  range_key    = "SK"

  # PK: LOCATION#<locationId> - one partition per restaurant's bookings.
  attribute {
    name = "PK"
    type = "S"
  }

  # SK: RESERVATION#<date>#<reservationId>. Date comes right after
  # "RESERVATION#" on purpose, same as slot occupancy: SK begins_with
  # "RESERVATION#<date>" gives staff a day's bookings (e.g. today's
  # reservations dashboard) with no separate index. Exact PK + SK gets one
  # specific reservation directly for status updates (arrived, cancelled,
  # no_show, etc.).
  attribute {
    name = "SK"
    type = "S"
  }

  # Native DynamoDB expiry on `ttl` (Unix epoch seconds). Unlike slot
  # occupancy, this isn't a same-day cleanup safety net - it's a data
  # retention control: once set, it auto-purges old reservation records
  # (and the customer PII on them - name, email, phone) after however long
  # your retention policy decides to keep them, rather than holding
  # customer booking history indefinitely.
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

  # NEW_AND_OLD_IMAGES (not just NEW_IMAGE) is required here - NotificationFn
  # compares OldImage.notice.id with NewImage.notice.id so a notice is sent
  # once, not on every later write of the same booking.
  stream_enabled   = true
  stream_view_type = "NEW_AND_OLD_IMAGES"

  tags = {
    Environment = var.environment
  }
}

# Invokes NotificationFn for every booking write that carries a guest
# notice (confirmed, changed, cancelled_by_guest, cancelled_by_restaurant,
# reminder - and M4's charge outcomes). The application decides what is
# worth a message by setting `notice`; this mapping only forwards those
# records, so NotificationFn is never invoked for irrelevant writes.
resource "aws_lambda_event_source_mapping" "notify_on_reservation_status_change" {
  event_source_arn  = aws_dynamodb_table.reservation.stream_arn
  function_name     = var.notification_lambda_arn # this can be NAME or ARN, but ARN is safer in case the Lambda is in a different account
  enabled           = true
  starting_position = "LATEST"
  batch_size        = 10

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

  # Only records the guest should hear about: a write that wants a message
  # sets `notice` = {id, type, at} on the booking (application
  # shared/reservations.py). The function skips records whose OldImage has
  # the same notice id, so later unrelated writes never resend.
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

  # A record that fails (e.g. SES throttling before anything was sent) is
  # retried on its own instead of re-running - and re-sending - the batch.
  function_response_types = ["ReportBatchItemFailures"]
}