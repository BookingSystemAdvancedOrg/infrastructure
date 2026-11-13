# AI phone agent (phone-agent/, CONTRACTS.md feature L, Run 0 addendum, built in Run 2).
module "phone_agent" {
  source      = "./phone-agent"
  environment = var.env
  region      = var.aws_region
  ecr_repository_urls = {
    "phone-agent"      = module.phone_agent_ecr.repository_url
    "phone-agent-call" = module.phone_agent_call_ecr.repository_url
    "phone-agent-jobs" = module.phone_agent_jobs_ecr.repository_url
  }
  tenant_table_name      = module.tenant.table_name
  tenant_table_arn       = module.tenant.table_arn
  location_table_name    = module.location.table_name
  location_id_index_name = module.location.location_id_index_name
  user_table_name        = module.user.table_name
  user_table_arn         = module.user.table_arn
  user_tenant_index_name = module.user.tenant_index_name
  # The agent's tools (ADR-L): invoke on these live aliases only, nothing on their tables.
  tool_function_arns = {
    "tenant-site-config"         = module.tenant_site_config_fn.alias_arn
    "get-availability"           = module.get_availability_fn.alias_arn
    "create-pending-reservation" = module.create_pending_reservation_fn.alias_arn
    "get-reservation"            = module.get_reservation_fn.alias_arn
    "mark-arrived"               = module.mark_arrived_fn.alias_arn
    "get-menu"                   = module.get_menu_fn.alias_arn
    "list-layout-version"        = module.list_layout_version_fn.alias_arn
  }
  notification_function_arn = module.notification_fn.alias_arn
  event_bus_name            = module.events.bus_name
  event_bus_arn             = module.events.bus_arn
  alert_topic_arn           = module.alerts.topic_arn
  voice_client              = var.voice_client
  telephony_client          = var.telephony_client
  agent_model_client        = var.agent_model_client
  phone_agent_model_id      = var.phone_agent_model_id
  phone_agent_voice_id      = var.phone_agent_voice_id
  phone_agent_tts_model     = var.phone_agent_tts_model
  elevenlabs_api_base       = var.elevenlabs_api_base
  call_reserved_concurrency = var.phone_agent_call_reserved_concurrency
}

variable "phone_agent_call_reserved_concurrency" {
  type        = number
  description = "Reserved concurrent executions for phone-agent-call (caps what a flood on its public Function URL can cost); -1 = unreserved. Dev sets 2; prod is UNDECIDED and stays -1 until the owner sets a value (2 is far too low for real restaurants). AWS refuses a reservation that leaves fewer than 10 unreserved in the account."
  sensitive   = false
  default     = -1

  validation {
    condition     = var.phone_agent_call_reserved_concurrency >= -1 && floor(var.phone_agent_call_reserved_concurrency) == var.phone_agent_call_reserved_concurrency
    error_message = "phone_agent_call_reserved_concurrency must be -1 (unreserved) or a whole number >= 0."
  }
}
