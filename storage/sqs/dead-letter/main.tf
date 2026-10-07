# Dead-letter queues for every asynchronous path in the platform. Every one
# of these should normally be EMPTY - a message here is work that ran out of
# retries. dlq-replay (compute/lambda/dlq-replay) redelivers them on a
# schedule; monitoring/alerts emails when something stays stuck.
#
#   lifecycle-stream     catering-requests stream batches catering-lifecycle
#                        failed (10 retries). Body: a POINTER to the records
#                        (stream ARN, shard, sequence numbers) - re-readable
#                        from the stream for 24h.
#   notification-stream  stream batches NotificationFn failed (5 retries), from
#                        all three streams it consumes: reservation, order and
#                        catering-requests. Body: same kind of pointer.
#   scheduled-invocation Failed scheduled runs of catering-lifecycle,
#                        no-show-check, reactivate-menu-item and
#                        expire-layout-version. EventBridge Scheduler invokes
#                        Lambda asynchronously, so each function's own
#                        on-failure destination (aws_lambda_function_event_invoke_config,
#                        Terraform-only) puts the invocation record here after
#                        Lambda's async retries - the original input is in
#                        requestPayload. catering-lifecycle's schedules also set
#                        this queue as their DeadLetterConfig (app code), which
#                        catches the rarer case of Scheduler not reaching
#                        Lambda at all - the body is then the original input.
#
# 14 days is the SQS maximum retention - the longest window to replay
# before a message is lost.

locals {
  prefix = var.environment == "prod" ? "" : "${var.environment}-"
  queues = {
    lifecycle_stream     = "${local.prefix}catering-lifecycle-stream-dlq"
    notification_stream  = "${local.prefix}notification-stream-dlq"
    scheduled_invocation = "${local.prefix}scheduled-invocation-dlq"
  }
}

resource "aws_sqs_queue" "this" {
  for_each = local.queues

  name                      = each.value
  message_retention_seconds = 1209600 # 14 days
  sqs_managed_sse_enabled   = true

  tags = {
    Environment = var.environment
  }
}

# Encryption in transit: refuse any request that isn't over TLS. Writers
# (Lambda's stream triggers and async destinations, EventBridge Scheduler)
# and the replay Lambda all use HTTPS already; this makes it a guarantee
# rather than a habit. Access itself is granted by each caller's IAM role -
# the queues stay private.
resource "aws_sqs_queue_policy" "this" {
  for_each = aws_sqs_queue.this

  queue_url = each.value.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid       = "DenyInsecureTransport"
        Effect    = "Deny"
        Principal = "*"
        Action    = "sqs:*"
        Resource  = each.value.arn
        Condition = {
          Bool = { "aws:SecureTransport" = "false" }
        }
      }
    ]
  })
}
