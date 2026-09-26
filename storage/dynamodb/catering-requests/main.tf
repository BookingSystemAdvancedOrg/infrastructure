
resource "aws_dynamodb_table" "catering_requests" {
  name         = var.environment == "prod" ? "catering-requests" : "${var.environment}-catering-requests"
  billing_mode = "PAY_PER_REQUEST"
  hash_key     = "PK"
  range_key    = "SK"

  # PK: LOCATION#<locationId> - keeps all requests for one restaurant in
  # a single partition, so staff can query everything for their location
  # in one read.
  attribute {
    name = "PK"
    type = "S"
  }

  # SK: REQUEST#<requestId> (UUID) - unique per submission. Combined with
  # PK this gives a direct GetItem for a single request and a Query for the
  # full list. Filtering by status (pending/accepted/rejected) happens in
  # app code; the set per location is small enough that a filter-after-read
  # is fine, and adding a status GSI would just increase write cost and
  # complexity for minimal gain at this scale.
  attribute {
    name = "SK"
    type = "S"
  }

  # No TTL - catering requests are business records that should be kept
  # for the full retention period; archiving is handled at the application
  # layer if needed.

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
