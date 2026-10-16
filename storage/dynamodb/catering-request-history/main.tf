
# Append-only history for catering requests: every offer version the owner
# saves and every audit-log entry. Kept out of catering-requests on purpose:
#
#   - IAM and the resource policy below can make this table append-only
#     (no UpdateItem/DeleteItem for anyone), which is what makes the audit
#     log usable as evidence in a dispute or chargeback.
#   - The owner's request list (Query on LOCATION#<id>) doesn't drag every
#     version and log line along with it.
resource "aws_dynamodb_table" "catering_request_history" {
  name         = var.environment == "prod" ? "catering-request-history" : "${var.environment}-catering-request-history"
  billing_mode = "PAY_PER_REQUEST"
  hash_key     = "PK"
  range_key    = "SK"

  # PK: REQUEST#<requestId> - one partition per catering request, so a
  # single Query returns its full history in order.
  attribute {
    name = "PK"
    type = "S"
  }

  # SK - two item types:
  #
  #   OFFER#v<0001> - one immutable offer version: line items, prices, VAT
  #     per line, delivery fee, terms text, validUntil and the SHA-256 of
  #     the rendered offer PDF. The customer signs exactly one of these;
  #     the zero-padded number keeps lexical order = version order.
  #   AUDIT#<ISO-8601 ts>#<seq> - one state change or action: actor
  #     (owner userId / customer / system / provider), action, from/to
  #     status, IP, user agent and any document hash involved.
  #   AUDIT#STRIPE#<evt id> / AUDIT#SIGNING#<event id> - entries written by
  #     the webhook handlers, keyed by the provider's event id so the
  #     attribute_not_exists(SK) write below doubles as webhook
  #     deduplication (a redelivered event can't be recorded twice).
  #
  # Writers must use PutItem with attribute_not_exists(SK), so an existing
  # entry can never be overwritten either.
  attribute {
    name = "SK"
    type = "S"
  }

  # No TTL - this is the evidence trail for signed agreements and invoices,
  # kept at least as long as the bookkeeping retention period (7 years).

  point_in_time_recovery {
    enabled = true
  }

  server_side_encryption {
    enabled = true
  }

  # Prod only: dropping this table would destroy the audit trail. Dev keeps
  # it off so the environment can still be torn down.
  deletion_protection_enabled = var.environment == "prod"

  tags = {
    Environment = var.environment
  }
}

# Belt and braces on top of IAM (no role is granted these actions): an
# explicit Deny for every principal, so even an admin session or a future
# over-broad role can't edit or delete history items. PutItem stays allowed -
# appending is the only way to change this table. Removing this policy is
# itself a deliberate, auditable act (dynamodb:DeleteResourcePolicy).
resource "aws_dynamodb_resource_policy" "append_only" {
  resource_arn = aws_dynamodb_table.catering_request_history.arn

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid       = "DenyHistoryMutation"
        Effect    = "Deny"
        Principal = "*"
        Action = [
          "dynamodb:UpdateItem",
          "dynamodb:DeleteItem",
          "dynamodb:BatchWriteItem",
          "dynamodb:PartiQLUpdate",
          "dynamodb:PartiQLDelete",
        ]
        Resource = aws_dynamodb_table.catering_request_history.arn
      }
    ]
  })
}
