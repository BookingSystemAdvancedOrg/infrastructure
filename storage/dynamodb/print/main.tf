# The print table: kitchen printers (Star CloudPRNT) and their print jobs,
# one partition per location like the order table, so tenant-purge deletes it
# with the rest of an offboarded restaurant's location data. No personal
# data: a job names the order, the ticket is rendered from the order when
# the printer fetches it (application shared/printing.py).
#
# Item types (PK | SK):
#
#   LOCATION#<l> | SETTINGS                 autoPrint, printerId, paperWidth, version
#   LOCATION#<l> | DEVICE#<deviceId>        name, secretHash (sha256), mac (bound on
#                                           the first poll), lastSeenAt, statusCode
#   LOCATION#<l> | JOB#<orderId>#auto       the order's one automatic job (conditional put)
#   LOCATION#<l> | JOB#<orderId>#cancel     "MAKULERAD" slip for a printed, cancelled order
#   LOCATION#<l> | JOB#<orderId>#m<ts>      "Skriv ut igen"
#   LOCATION#<l> | JOB#test#<ts>            test print for one device
#
# Jobs expire 30 days after they are created (ttl).

resource "aws_dynamodb_table" "print" {
  name         = var.environment == "prod" ? "print" : "${var.environment}-print"
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
    name = "queue"
    type = "S"
  }

  attribute {
    name = "dueAt"
    type = "S"
  }

  attribute {
    name = "deviceKey"
    type = "S"
  }

  # Sparse: only jobs that still need the printer (PENDING, PRINTING, FAILED)
  # carry queue = LOCATION#<l> and dueAt (next attempt, lease end, or a far
  # future value for FAILED). The printer's poll asks for the first job due
  # now; the admin banner counts the rest; the sweep scans this small index.
  global_secondary_index {
    name            = "queue"
    projection_type = "ALL"

    key_schema {
      attribute_name = "queue"
      key_type       = "HASH"
    }

    key_schema {
      attribute_name = "dueAt"
      key_type       = "RANGE"
    }
  }

  # Sparse: DEVICE# items only. The printer's URL names only its device id;
  # this finds its location (then the item is read from the table itself).
  global_secondary_index {
    name            = "byDevice"
    projection_type = "KEYS_ONLY"

    key_schema {
      attribute_name = "deviceKey"
      key_type       = "HASH"
    }
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
