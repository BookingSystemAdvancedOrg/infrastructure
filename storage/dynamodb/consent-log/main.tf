# Marketing consent log (application shared/consent.py): append-only proof
# of what each guest agreed to, per restaurant. A grant, a withdrawal and a
# suppression are each their own item; nothing is ever updated in place. The
# latest item per guest and channel is the consent state that every
# marketing send checks.
#
#   PK CONSENT#<tenantId>#<subject>   subject = sha256(tenant|channel|address)
#   SK <ISO time>#<random>            newest last; "<time>#S" = suppression
#
# GSI byTenant (tenantId, at): one restaurant's records, for data-retention
# (withdrawn -> suppression -> deleted) and tenant-purge (offboarding).
resource "aws_dynamodb_table" "consent_log" {
  name         = var.environment == "prod" ? "consent-log" : "${var.environment}-consent-log"
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
    name = "tenantId"
    type = "S"
  }

  attribute {
    name = "at"
    type = "S"
  }

  global_secondary_index {
    name            = "byTenant"
    projection_type = "ALL"

    key_schema {
      attribute_name = "tenantId"
      key_type       = "HASH"
    }

    key_schema {
      attribute_name = "at"
      key_type       = "RANGE"
    }
  }

  # Only suppression records carry ttl: a backstop in case data-retention
  # stops running. Grants and withdrawals never expire on their own.
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

  # This is evidence: a plan that deletes or replaces the table must fail
  # in prod (set false in an apply first if that is really intended).
  deletion_protection_enabled = var.environment == "prod"

  tags = {
    Environment = var.environment
  }
}
