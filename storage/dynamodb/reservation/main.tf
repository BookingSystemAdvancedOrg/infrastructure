
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

  # NEW_AND_OLD_IMAGES (not just NEW_IMAGE) is required here - the filter
  # below has to compare OldImage.status against NewImage.status to catch
  # only the transition into "reserved", not every write already sitting
  # in that state.
  stream_enabled   = true
  stream_view_type = "NEW_AND_OLD_IMAGES"

  tags = {
    Environment = var.environment
  }
}

# Invokes NotificationFn on the two customer-facing status transitions that
# warrant an SMS. Filter blocks within one filter_criteria are OR'd - a
# stream record only needs to match one of them to be delivered:
#
#   1. pending -> reserved: booking confirmed.
#   2. reserved -> a terminal cancel/no-show outcome: tells the customer
#      whether they were charged and why. NewImage is an explicit allow-list
#      of the five terminal statuses (not "anything-but pending, arrived"),
#      same reasoning as the OldImage exact-match below - a future status
#      value added to the enum won't silently start matching here.
#
# Anchoring filter 2's OldImage to exactly "reserved" also rules out
# resolving a failed charge later (e.g. cancelled_charge_failed ->
# cancelled_charged once the payment link is paid) triggering this - that
# transition's OldImage is never "reserved", so it can't match either
# pattern.
#
# Filtering happens here, at the event source mapping, so NotificationFn is
# never even invoked for irrelevant stream records.
resource "aws_lambda_event_source_mapping" "notify_on_reservation_status_change" {
  event_source_arn  = aws_dynamodb_table.reservation.stream_arn
  function_name     = var.notification_lambda_arn # this can be NAME or ARN, but ARN is safer in case the Lambda is in a different account
  enabled           = true
  starting_position = "LATEST"
  batch_size        = 10

  filter_criteria {
    filter {
      pattern = jsonencode({
        eventName = ["MODIFY"]
        dynamodb = {
          OldImage = {
            status = { S = ["pending"] }
          }
          NewImage = {
            status = { S = ["reserved"] }
          }
        }
      })
    }
    filter {
      pattern = jsonencode({
        eventName = ["MODIFY"]
        dynamodb = {
          OldImage = {
            status = { S = ["reserved"] }
          }
          NewImage = {
            status = { S = ["cancelled_no_charge", "cancelled_charged", "cancelled_charge_failed", "no_show_charged", "no_show_charge_failed"] }
          }
        }
      })
    }
  }
}