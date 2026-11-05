# ADR-H test plan: the ledger is append only. moto (application tests) cannot
# enforce DynamoDB resource policies, so this asserts the Terraform side with
# a mocked AWS provider (no AWS account, nothing created):
#   terraform -chdir=personalliggare init -backend=false && terraform -chdir=personalliggare test
# The real effect (Lambda role refused, TTL deletes still allowed) is
# unverified until it runs in AWS (STATUS.md).

mock_provider "aws" {
  mock_data "aws_caller_identity" {
    defaults = { account_id = "123456789012" }
  }
  mock_resource "aws_dynamodb_table" {
    defaults = { arn = "arn:aws:dynamodb:eu-north-1:123456789012:table/dev-personalliggare-ledger" }
  }
  mock_resource "aws_iam_role" {
    defaults = { arn = "arn:aws:iam::123456789012:role/dev-personalliggare-role" }
  }
  mock_resource "aws_lambda_function" {
    defaults = { arn = "arn:aws:lambda:eu-north-1:123456789012:function:dev-personalliggare" }
  }
  mock_resource "aws_lambda_alias" {
    defaults = { arn = "arn:aws:lambda:eu-north-1:123456789012:function:dev-personalliggare:live" }
  }
}

variables {
  environment            = "dev"
  region                 = "eu-north-1"
  ecr_repository_url     = "123456789012.dkr.ecr.eu-north-1.amazonaws.com/dev-personalliggare"
  tenant_table_name      = "dev-tenant"
  location_table_name    = "dev-location"
  location_id_index_name = "byLocationId"
  user_table_name        = "dev-user"
  event_bus_name         = "dev-booqy-events"
  event_bus_arn          = "arn:aws:events:eu-north-1:123456789012:event-bus/dev-booqy-events"
  alert_topic_arn        = "arn:aws:sns:eu-north-1:123456789012:dev-alerts"
}

run "ledger_is_append_only" {
  command = apply

  assert {
    condition = toset(jsondecode(aws_dynamodb_resource_policy.ledger_append_only.policy).Statement[0].Action) == toset([
      "dynamodb:UpdateItem", "dynamodb:DeleteItem", "dynamodb:BatchWriteItem", "dynamodb:PartiQLUpdate", "dynamodb:PartiQLDelete",
    ])
    error_message = "The ledger resource policy must deny every mutation"
  }

  assert {
    condition = (jsondecode(aws_dynamodb_resource_policy.ledger_append_only.policy).Statement[0].Effect == "Deny"
    && jsondecode(aws_dynamodb_resource_policy.ledger_append_only.policy).Statement[0].Principal == "*")
    error_message = "The ledger policy must be a Deny for every principal"
  }

  assert {
    condition = toset([for s in jsondecode(aws_iam_role_policy.fn.policy).Statement : s.Action if s.Sid == "LedgerAppendAndRead"][0]) == toset([
      "dynamodb:PutItem", "dynamodb:GetItem", "dynamodb:Query",
    ])
    error_message = "The role may only append to and read the ledger"
  }

  assert {
    condition     = aws_dynamodb_table.ledger.deletion_protection_enabled
    error_message = "Ledger deletion protection must be on in every environment"
  }

  assert {
    condition     = aws_dynamodb_table.ledger.ttl[0].enabled && aws_dynamodb_table.ledger.point_in_time_recovery[0].enabled
    error_message = "Ledger TTL and PITR must be on"
  }
}
