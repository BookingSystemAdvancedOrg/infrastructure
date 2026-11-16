# Error reports from Booqy Admin ("Rapportera till Booqy"), written by the
# support-reports Lambda and listed in Booqy Console (Reports).
#
#   PK REPORTS          SK <reportId>   one report (tenant, user sub, page path,
#                                       error code, request id, app version,
#                                       user agent), kept 180 days
#   PK DEDUPE#<hash>    SK -            the same report within 10 minutes
#
# <reportId> starts with the UTC time, so a Query on REPORTS with
# ScanIndexForward = false is newest first. Both kinds expire through the
# `ttl` attribute. No secrets, tokens or form contents are ever stored.
resource "aws_dynamodb_table" "this" {
  name         = var.environment == "prod" ? "support-reports" : "${var.environment}-support-reports"
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
