
resource "aws_dynamodb_table" "location" {
  name         = var.environment == "prod" ? "location" : "${var.environment}-location"
  billing_mode = "PAY_PER_REQUEST"
  hash_key     = "PK"
  range_key    = "SK"

  # PK: TENANT#<tenantId> - every location lives in its tenant's partition,
  # so "list my locations" is a Query that physically cannot return another
  # tenant's rows. (Was the constant "PLATFORM" in the single-customer
  # model; a shared partition across tenants would make every location list
  # one forgotten filter away from a cross-tenant leak.)
  attribute {
    name = "PK"
    type = "S"
  }

  # SK: LOCATION#<locationId>. PK + SK together get one specific location's
  # record (including its booking policy) directly. Every item also carries
  # tenantId and locationId as plain attributes.
  attribute {
    name = "SK"
    type = "S"
  }

  # Public routes only know {locationId} (from the URL). This index resolves
  # locationId -> tenantId + settings in one Query - the first step of every
  # request's tenant check. locationIds are random (ULID/UUID), so they're
  # unique across tenants.
  attribute {
    name = "locationId"
    type = "S"
  }

  global_secondary_index {
    name            = "byLocationId"
    projection_type = "ALL"

    key_schema {
      attribute_name = "locationId"
      key_type       = "HASH"
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
