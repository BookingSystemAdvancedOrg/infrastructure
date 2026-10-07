# The control-plane table: one row set per tenant (a restaurant company -
# the customer you sign), plus the global lookups that keep tenant data
# unique and routable. Everything a new customer needs is a row here, not a
# Terraform change - that's what makes onboarding code-less.
#
# Item types (PK | SK):
#
#   TENANT#<tenantId>      | PROFILE          name, legalName, orgNumber, slug,
#                                              status (provisioning | active |
#                                              suspended | provisioning_failed |
#                                              offboarding | offboarded),
#                                              planId, entitlements {maxLocations,
#                                              features{...}}, locationCount,
#                                              stripe {accountId, chargesEnabled,
#                                              payoutsEnabled, detailsSubmitted,
#                                              taxRates{key: txr_}}, primaryDomain,
#                                              senderName, replyToEmail, branding.
#                                              GSI1PK = "TENANT", GSI1SK = slug
#   TENANT#<tenantId>      | DOMAIN#<host>    status (pending_dns | pending_validation |
#                                              active | validation_timeout |
#                                              removing | failed),
#                                              kind (platform | custom),
#                                              distributionTenantId, cnameTarget
#   TENANT#<tenantId>      | AUDIT#<ts>#<id>  who changed what (plan, status, ...)
#   SLUG#<slug>            | TENANT           tenantId - makes slugs unique
#   DOMAIN#<host>          | TENANT           tenantId - makes a host belong to
#                                              exactly one tenant; public
#                                              /site-config resolves through it
#   STRIPE_ACCOUNT#<acct>  | TENANT           tenantId - Connect webhooks carry
#                                              only event.account
#   PLAN#<planId>          | PLAN             plan catalog, seeded from
#                                              var.plans by Terraform.
#                                              GSI1PK = "PLAN", GSI1SK = planId
#
# Uniqueness rows (SLUG#, DOMAIN#, STRIPE_ACCOUNT#) are always written in
# the same TransactWriteItems as the tenant row they point at, conditioned
# on attribute_not_exists(PK) - two tenants can never claim the same slug,
# domain or Stripe account, even under concurrent requests.

locals {
  table_name = var.environment == "prod" ? "tenant" : "${var.environment}-tenant"
}

resource "aws_dynamodb_table" "tenant" {
  name         = local.table_name
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

  # Sparse index - only PROFILE and PLAN rows carry GSI1PK/GSI1SK, so a
  # Query on GSI1PK = "TENANT" lists every tenant (the platform dashboard's
  # list view) and GSI1PK = "PLAN" the plan catalog, without scanning
  # domains, audit entries and lookups.
  attribute {
    name = "GSI1PK"
    type = "S"
  }

  attribute {
    name = "GSI1SK"
    type = "S"
  }

  global_secondary_index {
    name            = "GSI1"
    projection_type = "ALL"

    key_schema {
      attribute_name = "GSI1PK"
      key_type       = "HASH"
    }

    key_schema {
      attribute_name = "GSI1SK"
      key_type       = "RANGE"
    }
  }

  point_in_time_recovery {
    enabled = true
  }

  server_side_encryption {
    enabled = true
  }

  # Losing this table means losing which data belongs to which customer.
  deletion_protection_enabled = var.environment == "prod"

  tags = {
    Environment = var.environment
  }
}

# Plan catalog. Changing what a package includes is a tfvars change here;
# moving ONE customer to another package (or giving them extra locations)
# is a platform-dashboard action that only touches their PROFILE row.
resource "aws_dynamodb_table_item" "plan" {
  for_each = var.plans

  table_name = aws_dynamodb_table.tenant.name
  hash_key   = aws_dynamodb_table.tenant.hash_key
  range_key  = aws_dynamodb_table.tenant.range_key

  item = jsonencode({
    PK           = { S = "PLAN#${each.key}" }
    SK           = { S = "PLAN" }
    GSI1PK       = { S = "PLAN" }
    GSI1SK       = { S = each.key }
    planId       = { S = each.key }
    name         = { S = each.value.name }
    maxLocations = { N = tostring(each.value.max_locations) }
    features = {
      M = { for feature, enabled in each.value.features : feature => { BOOL = enabled } }
    }
  })
}
