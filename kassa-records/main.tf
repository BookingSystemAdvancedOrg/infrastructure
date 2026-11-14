# Kassa records, prod only (kassa-records.tf). Kassa, the till, was removed on
# 2026-11-14: Booqy is online only. Its two tables stay in prod because
# kassaregister data is bookkeeping material, kept at least 7 years after the
# end of the calendar year (BFL 7 kap. 2 §). Nothing reads or writes them any
# more; they are kept exactly as Kassa defined them (attributes, PITR,
# deletion protection, the journal's append-only Deny policy).
#
#   kassa          registers, closed bills, receipt pointers
#   kassa-journal  the journal memory: append-only, no TTL
#
# No lifecycle.prevent_destroy: in dev the moved blocks in kassa-records.tf
# land on an instance that is not declared (count = 0) and Terraform must be
# able to destroy it there. Prod relies on deletion_protection_enabled.

locals {
  prefix = var.environment == "prod" ? "" : "${var.environment}-"
  name   = "${local.prefix}kassa"
}

# PK LOCATION#<locationId>; SK REGISTER#<id> | BILL#<id> | RCPT#<registerId>#<seq>.
# Closed and voided bills expire (ttl) after 90 days; registers and receipt
# pointers have no ttl.
resource "aws_dynamodb_table" "kassa" {
  name         = local.name
  billing_mode = "PAY_PER_REQUEST"
  hash_key     = "PK"
  range_key    = "SK"

  attribute {
    name = "PK"
    type = "S"
  }

  attribute {
    name = "SK"
    type = "S"
  }

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

  deletion_protection_enabled = var.environment == "prod"

  tags = {
    Environment = var.environment
  }
}

# PK REG#<registerId>, SK J#<12-digit journal sequence>: one item per
# registration (receipt, return, copy, training receipt, X/Z report, float,
# mode change, control system status, removed line), each with the SHA-256
# of the one before. byDay (regDay = REG#<registerId>#<local date>) serves
# the day's list and the XML export by period.
resource "aws_dynamodb_table" "journal" {
  name         = "${local.name}-journal"
  billing_mode = "PAY_PER_REQUEST"
  hash_key     = "PK"
  range_key    = "SK"

  attribute {
    name = "PK"
    type = "S"
  }

  attribute {
    name = "SK"
    type = "S"
  }

  attribute {
    name = "regDay"
    type = "S"
  }

  global_secondary_index {
    name            = "byDay"
    projection_type = "ALL"

    key_schema {
      attribute_name = "regDay"
      key_type       = "HASH"
    }

    key_schema {
      attribute_name = "SK"
      key_type       = "RANGE"
    }
  }

  # No TTL: the journal is bookkeeping material, kept at least 7 years after
  # the end of the calendar year (BFL 7 kap. 2 §). data-retention and
  # tenant-purge have no access to this table.

  point_in_time_recovery {
    enabled = true
  }

  server_side_encryption {
    enabled = true
  }

  # Prod: dropping the table would destroy the journal memory.
  deletion_protection_enabled = var.environment == "prod"

  tags = {
    Environment = var.environment
  }
}

# An explicit Deny for every principal, so nothing can change or delete a
# registration (SKVFS 2014:9 6 kap. 1 §). Appending stays allowed. Removing
# this policy is itself a deliberate, logged act. Same pattern as the
# catering request history.
resource "aws_dynamodb_resource_policy" "journal_append_only" {
  resource_arn = aws_dynamodb_table.journal.arn

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid       = "DenyJournalMutation"
        Effect    = "Deny"
        Principal = "*"
        Action = [
          "dynamodb:UpdateItem",
          "dynamodb:DeleteItem",
          "dynamodb:BatchWriteItem",
          "dynamodb:PartiQLUpdate",
          "dynamodb:PartiQLDelete",
        ]
        Resource = aws_dynamodb_table.journal.arn
      }
    ]
  })
}
