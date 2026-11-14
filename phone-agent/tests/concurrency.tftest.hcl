# Reserved concurrency of phone-agent-call: unreserved unless the environment
# sets call_reserved_concurrency (dev = 2, prod undecided). Mocked AWS, plan
# only (no AWS account, nothing created):
#   terraform -chdir=phone-agent init -backend=false && terraform -chdir=phone-agent test

mock_provider "aws" {
  mock_data "aws_caller_identity" {
    defaults = { account_id = "123456789012" }
  }
}

variables {
  environment = "dev"
  region      = "eu-north-1"
  ecr_repository_urls = {
    "phone-agent"      = "123456789012.dkr.ecr.eu-north-1.amazonaws.com/dev-phone-agent"
    "phone-agent-call" = "123456789012.dkr.ecr.eu-north-1.amazonaws.com/dev-phone-agent-call"
    "phone-agent-jobs" = "123456789012.dkr.ecr.eu-north-1.amazonaws.com/dev-phone-agent-jobs"
  }
  tenant_table_name      = "dev-tenant"
  tenant_table_arn       = "arn:aws:dynamodb:eu-north-1:123456789012:table/dev-tenant"
  location_table_name    = "dev-location"
  location_table_arn     = "arn:aws:dynamodb:eu-north-1:123456789012:table/dev-location"
  location_id_index_name = "byLocationId"
  user_table_name        = "dev-user"
  user_table_arn         = "arn:aws:dynamodb:eu-north-1:123456789012:table/dev-user"
  user_tenant_index_name = "byTenant"
  tool_function_arns = {
    "tenant-site-config"         = "arn:aws:lambda:eu-north-1:123456789012:function:dev-tenant-site-config:live"
    "get-availability"           = "arn:aws:lambda:eu-north-1:123456789012:function:dev-get-availability:live"
    "create-pending-reservation" = "arn:aws:lambda:eu-north-1:123456789012:function:dev-create-pending-reservation:live"
    "get-reservation"            = "arn:aws:lambda:eu-north-1:123456789012:function:dev-get-reservation:live"
    "mark-arrived"               = "arn:aws:lambda:eu-north-1:123456789012:function:dev-mark-arrived:live"
    "get-menu"                   = "arn:aws:lambda:eu-north-1:123456789012:function:dev-get-menu:live"
    "list-layout-version"        = "arn:aws:lambda:eu-north-1:123456789012:function:dev-list-layout-version:live"
  }
  notification_function_arn = "arn:aws:lambda:eu-north-1:123456789012:function:dev-notification:live"
  event_bus_name            = "dev-booqy-events"
  event_bus_arn             = "arn:aws:events:eu-north-1:123456789012:event-bus/dev-booqy-events"
  alert_topic_arn           = "arn:aws:sns:eu-north-1:123456789012:dev-alerts"
  voice_client              = "simulator"
  telephony_client          = "simulator"
  agent_model_client        = "simulator"
  phone_agent_model_id      = ""
}

run "unreserved_by_default" {
  command = plan

  assert {
    condition     = alltrue([for f in aws_lambda_function.fn : f.reserved_concurrent_executions == -1])
    error_message = "Without call_reserved_concurrency every phone-agent function must stay unreserved"
  }
}

run "dev_caps_the_call_function_only" {
  command = plan

  variables {
    call_reserved_concurrency = 2
  }

  assert {
    condition     = aws_lambda_function.fn["phone-agent-call"].reserved_concurrent_executions == 2
    error_message = "phone-agent-call must reserve the configured concurrency"
  }

  assert {
    condition = (aws_lambda_function.fn["phone-agent"].reserved_concurrent_executions == -1
    && aws_lambda_function.fn["phone-agent-jobs"].reserved_concurrent_executions == -1)
    error_message = "Only phone-agent-call is capped"
  }
}

run "rejects_an_invalid_value" {
  command = plan

  variables {
    call_reserved_concurrency = -2
  }

  expect_failures = [var.call_reserved_concurrency]
}
