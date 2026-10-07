
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

  # SK - two item types share the location partition:
  #
  #   REQUEST#<requestId> (UUID) - the request/order "head" item. Carries the
  #     workflow status (requested -> offer_sent -> signed -> confirmed ->
  #     delivered -> closed, or declined / expired / cancelled_by_restaurant),
  #     a numeric `version` used as an optimistic lock on every update, the
  #     frozen price snapshot, the current offer version, validUntil, and the
  #     mirrored Stripe invoice id/status. Offer versions and the audit log
  #     do NOT live here - they're in catering-request-history, so this
  #     partition stays small and the owner's list query stays clean.
  #
  #   CAPACITY#<yyyy-mm-dd> - servings held for one delivery date. Reserved
  #     when the owner sends an offer and released on decline/expiry/
  #     restaurant cancellation, always in the SAME TransactWriteItems call
  #     as the head item's status change, so capacity and status can never
  #     drift apart.
  #
  # Filtering requests by status still happens in app code; the set per
  # location is small enough that a filter-after-read is fine.
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

  # NEW_AND_OLD_IMAGES - both consumers below need to see what a write
  # changed: catering-lifecycle compares OldImage.status with
  # NewImage.status to detect a transition, and NotificationFn does the
  # same to avoid re-sending an email on a write that didn't change status
  # (e.g. the Stripe webhook mirroring invoiceStatus onto a confirmed
  # order). Changing the view type replaces the stream (new stream ARN);
  # Terraform re-creates both event source mappings against it.
  stream_enabled   = true
  stream_view_type = "NEW_AND_OLD_IMAGES"

  tags = {
    Environment = var.environment
  }
}

# Invokes NotificationFn for catering emails. Two filters, OR'd:
#
#   1. INSERT of a new request - the owner's link-only "new catering
#      request" email (no offer details in the body, by design) and the
#      customer's confirmation. Both "pending" (status written by the
#      pre-workflow catering-requests code) and "requested" (the new
#      workflow's initial status) match, so notifications keep working
#      while the backend is migrated.
#   2. MODIFY of a request head item into a customer-facing status.
#      NewImage is an explicit allow-list, same reasoning as the
#      reservation table - a future status won't silently start emailing.
#      The handler must still compare OldImage.status vs NewImage.status:
#      a write that keeps status "confirmed" (invoice mirroring) matches
#      this pattern too.
#
# CAPACITY#<date> items never match - they carry no status attribute and
# filter 2 is anchored to SK prefix REQUEST#.
#
# Failure handling: a broken handler or an SES outage must not block this
# shard for 24 hours, so retries are capped and the batch is bisected to
# isolate a poison record; anything still failing goes to the DLQ (stream
# metadata only - the record itself can be re-read from the stream within
# its 24h retention).
resource "aws_lambda_event_source_mapping" "notify_on_catering_request_change" {
  event_source_arn  = aws_dynamodb_table.catering_requests.stream_arn
  function_name     = var.notification_lambda_arn # this can be NAME or ARN, but ARN is safer in case the Lambda is in a different account
  enabled           = true
  starting_position = "LATEST"
  batch_size        = 10

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
        eventName = ["INSERT"]
        dynamodb = {
          NewImage = {
            status = { S = ["pending", "requested"] }
          }
        }
      })
    }
    filter {
      pattern = jsonencode({
        eventName = ["MODIFY"]
        dynamodb = {
          Keys = {
            SK = { S = [{ prefix = "REQUEST#" }] }
          }
          NewImage = {
            status = { S = ["offer_sent", "signed", "confirmed", "declined", "expired", "cancelled_by_restaurant"] }
          }
        }
      })
    }
  }
}

# Invokes catering-lifecycle on every write to a request head item. The
# lifecycle function owns everything that hangs off a status change:
# creating/deleting the per-request timers (EventBridge Scheduler),
# issuing the Stripe invoice for company customers on "confirmed", and
# releasing capacity. It compares OldImage/NewImage itself - DynamoDB
# filters can't express "status changed", and head-item writes are few
# per order, so the extra invocations are negligible.
#
# ReportBatchItemFailures: the handler returns batchItemFailures so one bad
# record doesn't force the whole batch to be retried (lifecycle actions are
# idempotent anyway - schedules are created with deterministic names).
resource "aws_lambda_event_source_mapping" "lifecycle_on_catering_request_change" {
  event_source_arn  = aws_dynamodb_table.catering_requests.stream_arn
  function_name     = var.lifecycle_lambda_arn
  enabled           = true
  starting_position = "LATEST"
  batch_size        = 10

  maximum_retry_attempts         = 10
  bisect_batch_on_function_error = true
  function_response_types        = ["ReportBatchItemFailures"]

  destination_config {
    on_failure {
      destination_arn = var.lifecycle_dlq_arn
    }
  }

  filter_criteria {
    filter {
      pattern = jsonencode({
        eventName = ["INSERT", "MODIFY"]
        dynamodb = {
          Keys = {
            SK = { S = [{ prefix = "REQUEST#" }] }
          }
        }
      })
    }
  }
}
