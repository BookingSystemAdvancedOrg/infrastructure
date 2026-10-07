# Offer PDF renderer. Separate from catering-offer because the PDF toolchain
# (e.g. WeasyPrint + fonts) makes for a large image that needs far more
# memory than the API handlers - giving it its own function keeps the owner
# API's cold starts fast and its memory (and cost) small.

locals {
  function_name = var.environment == "prod" ? "catering-document" : "${var.environment}-catering-document"
}

# Declared explicitly, not left to be auto-created on first invoke, so log
# retention is actually controlled instead of defaulting to "never expire".
resource "aws_cloudwatch_log_group" "this" {
  name              = "/aws/lambda/${local.function_name}"
  retention_in_days = 30

  tags = {
    Environment = var.environment
  }
}

resource "aws_lambda_function" "this" {
  function_name = local.function_name
  role          = var.role_arn
  package_type  = "Image"
  image_uri     = "${var.ecr_repository_url}:latest"
  architectures = ["arm64"]

  timeout     = 60
  memory_size = 2048

  environment {
    variables = {
      TENANT_TABLE_NAME                   = var.tenant_table_name
      LOCATION_ID_INDEX_NAME              = var.location_id_index_name
      ENVIRONMENT                         = var.environment
      CATERING_REQUEST_HISTORY_TABLE_NAME = var.catering_request_history_table_name
      LOCATION_TABLE_NAME                 = var.location_table_name
      CATERING_DOCUMENTS_BUCKET_NAME      = var.catering_documents_bucket_name
    }
  }

  tags = {
    Environment = var.environment
  }

  depends_on = [aws_cloudwatch_log_group.this]
}
