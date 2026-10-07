
resource "aws_dynamodb_table" "user" {
  name         = var.environment == "prod" ? "user" : "${var.environment}-user"
  billing_mode = "PAY_PER_REQUEST"
  hash_key     = "PK"
  range_key    = "SK"

  # PK: USER#<cognitoSub>. Keyed by sub rather than location - the frequent
  # operation is "look up the calling user's role/location from their
  # token" (used by BlockTableFn and anything else doing per-request
  # authorization), which this makes a direct GetItem, no Query, no GSI.
  attribute {
    name = "PK"
    type = "S"
  }

  # SK: fixed constant "PROFILE" - PK already uniquely identifies the user
  # (one item per sub), so SK doesn't need to distinguish anything. It
  # exists only so this table follows the same PK+SK composite-key shape
  # as the rest of the tables in this project.
  attribute {
    name = "SK"
    type = "S"
  }

  # Every profile carries tenantId (= the user's immutable custom:tenant_id
  # in Cognito). "List a tenant's staff" - and suspending/offboarding a
  # tenant, which disables all of its users - is a Query on this index.
  # Never Scan this table for that: a Scan reads every tenant's staff.
  attribute {
    name = "tenantId"
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
      attribute_name = "PK"
      key_type       = "RANGE"
    }
  }

  point_in_time_recovery {
    enabled = true
  }

  server_side_encryption {
    enabled = true
  }

  tags = {
    Environment = var.environment
  }
}
