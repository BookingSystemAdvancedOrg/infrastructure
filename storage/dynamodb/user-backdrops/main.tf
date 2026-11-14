# Each signed-in user's personal background image library (Booqy Admin:
# user-backdrop Lambda; Booqy Console: platform-tenants). The images
# themselves are in the user-backdrops bucket (storage/s3/user-backdrops).
#
#   PK USER#<tenantId>#<sub>   admin user      SK IMG#<id>   one image
#   PK OPERATOR#<sub>          console operator SK SELECTED   the chosen image
#
# <id> sorts by upload time, so a Query on PK is newest-last. At most 20
# images per user (checked by the code before an upload and on complete).
#
# GSI byTenant (tenantId, PK), keys only: every admin user's items of one
# restaurant, for tenant-purge. Operator items carry no tenantId.
resource "aws_dynamodb_table" "this" {
  name         = var.environment == "prod" ? "user-backdrops" : "${var.environment}-user-backdrops"
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

  global_secondary_index {
    name            = "byTenant"
    projection_type = "KEYS_ONLY"

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
