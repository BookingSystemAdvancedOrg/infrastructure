# AI phone agent, AWS-only test line (owner 2026-11-13, dev only): Amazon
# Connect in Frankfurt + a Swedish Lex V2 bot + Polly Elin, relaying every
# utterance to phone-agent-call:live. Off unless phone_test_line_enabled.
provider "aws" {
  alias  = "eu_central_1"
  region = "eu-central-1"
}

variable "phone_test_line_enabled" {
  type        = bool
  description = "The AWS-only phone test line (Amazon Connect + Lex + Polly in eu-central-1). Dev only."
  sensitive   = false
  default     = false

  validation {
    condition     = !var.phone_test_line_enabled || var.env == "dev"
    error_message = "phone_test_line_enabled is for dev only."
  }
}

variable "phone_test_line_country" {
  type        = string
  description = "Country code of the test line's number (SE, or DE when Swedish numbers need paperwork)."
  sensitive   = false
  default     = "SE"
}

variable "phone_test_line_greeting" {
  type        = string
  description = "The test line's first sentence: the art. 50 disclosure for the test restaurant (Booqy's greeting text)."
  sensitive   = false
  default     = "Hej, du pratar med Booqy-assistenten, en AI-assistent för Restaurant 1. Vad kan jag hjälpa dig med?"
}

module "phone_test_line" {
  count  = var.phone_test_line_enabled ? 1 : 0
  source = "./phone-test-line"
  providers = {
    aws = aws.eu_central_1
  }
  environment    = var.env
  call_alias_arn = module.phone_agent.call_alias_arn
  greeting       = var.phone_test_line_greeting
  country_code   = var.phone_test_line_country
}

variable "phone_test_line_location" {
  type        = object({ tenant_id = string, location_id = string })
  description = "The dev test restaurant the test line's number answers for (its NUMBER# row in the phone-agent table)."
  sensitive   = false
  default     = null
}

# The number -> location pointer the agent resolves a call by (ADR-L data model, GSI byNumber).
resource "aws_dynamodb_table_item" "phone_test_line_number" {
  count      = var.phone_test_line_enabled && var.phone_test_line_location != null ? 1 : 0
  table_name = module.phone_agent.table_name
  hash_key   = "PK"
  range_key  = "SK"
  item = jsonencode({
    PK          = { S = "TENANT#${var.phone_test_line_location.tenant_id}" }
    SK          = { S = "NUMBER#${module.phone_test_line[0].phone_number}" }
    tenantId    = { S = var.phone_test_line_location.tenant_id }
    locationId  = { S = var.phone_test_line_location.location_id }
    locationIds = { L = [{ S = var.phone_test_line_location.location_id }] }
    GSI1PK      = { S = "NUMBER#${module.phone_test_line[0].phone_number}" }
    GSI1SK      = { S = "${var.phone_test_line_location.tenant_id}#${var.phone_test_line_location.location_id}" }
  })
}

output "phone_test_line_number" {
  description = "Call this number to talk to the phone agent (dev test line)"
  value       = try(module.phone_test_line[0].phone_number, null)
}
